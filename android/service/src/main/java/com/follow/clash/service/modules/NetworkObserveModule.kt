package com.follow.clash.service.modules

import android.app.Service
import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkCapabilities.TRANSPORT_SATELLITE
import android.net.NetworkCapabilities.TRANSPORT_USB
import android.net.NetworkRequest
import android.os.Build
import androidx.core.content.getSystemService
import com.follow.clash.core.Core
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.util.concurrent.ConcurrentHashMap

private const val DNS_PREFS_NAME = "flclash_dns_cache"
private const val DNS_PREFS_KEY = "last_dns_list"
private const val DNS_PREFS_JOIN = "|"

private data class NetworkInfo(
    @Volatile var losingUntilMillis: Long = 0,
    @Volatile var dnsList: List<InetAddress> = emptyList(),
) {
    val priorityPenalty: Int
        get() = if (losingUntilMillis > System.currentTimeMillis()) 10 else 0
}

internal class NetworkObserveModule(private val service: Service) : ServiceModule {

    private val networkInfos = ConcurrentHashMap<Network, NetworkInfo>()
    private val connectivity by lazy {
        service.getSystemService<ConnectivityManager>()
    }
    private var currentDnsList = listOf<String>()

    // SharedPreferences 持久化层：缓存最后已知良好的 DNS 列表，
    // 供冷启动/进程被杀重启后、首个 NetworkCallback 到达前使用。
    private val prefs by lazy {
        service.getSharedPreferences(DNS_PREFS_NAME, Context.MODE_PRIVATE)
    }

    private val request = NetworkRequest.Builder().apply {
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            addCapability(NetworkCapabilities.NET_CAPABILITY_FOREGROUND)
        }
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
    }.build()

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            networkInfos[network] = NetworkInfo()
            updateDns()
        }

        override fun onLosing(network: Network, maxMsToLive: Int) {
            networkInfos[network]?.losingUntilMillis = System.currentTimeMillis() + maxMsToLive
            updateDns()
        }

        override fun onLost(network: Network) {
            networkInfos.remove(network)
            updateDns()
        }

        override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
            networkInfos[network]?.dnsList = linkProperties.dnsServers
            updateDns()
        }
    }

    override fun start() {
        // 冷启动时 NetworkCallback 尚未回调，networkInfos 为空。
        // 加载上次持久化的 DNS 列表，让 core 在首个 NetworkCallback 到达前
        // 就有 DNS 可用，避免冷启动/进程被杀重启后的"无网假死"窗口。
        // 注意：此处不再调用 updateDns()——原始调用在 networkInfos 为空时是
        // no-op（空==空提前返回），但若已加载 persisted 到 currentDnsList，
        // 再调用会导致 emptyList != persisted 而立即清空刚加载的值。
        if (currentDnsList.isEmpty()) {
            val persisted = loadPersistedDns()
            if (persisted.isNotEmpty()) {
                currentDnsList = persisted
                Core.updateDNS(persisted.joinToString(","))
            }
        }
        connectivity?.registerNetworkCallback(request, callback)
    }

    private fun networkPriority(entry: Map.Entry<Network, NetworkInfo>): Int {
        val capabilities = connectivity?.getNetworkCapabilities(entry.key)
        return when {
            capabilities == null -> 100
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> 90
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 0
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> 1
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                capabilities.hasTransport(TRANSPORT_USB) -> 2

            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> 3
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 4
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM &&
                capabilities.hasTransport(TRANSPORT_SATELLITE) -> 5

            else -> 20
        } + entry.value.priorityPenalty
    }

    @Synchronized
    private fun updateDns() {
        val dnsList = networkInfos.asSequence()
            .minByOrNull(::networkPriority)
            ?.value
            ?.dnsList
            .orEmpty()
            .map { address -> address.asSocketAddressText(DNS_PORT) }
            .distinct()
        if (dnsList == currentDnsList) {
            return
        }
        currentDnsList = dnsList
        Core.updateDNS(dnsList.joinToString(","))
        // 持久化最新非空 DNS 列表，保留"最后已知良好"值供下次冷启动使用。
        // 网络完全丢失（dnsList 空）时不清除缓存，避免下次冷启动无 DNS 可用。
        // apply() 异步写盘，不阻塞 NetworkCallback 线程。
        if (dnsList.isNotEmpty()) {
            prefs.edit().putString(DNS_PREFS_KEY, dnsList.joinToString(DNS_PREFS_JOIN)).apply()
        }
    }

    private fun loadPersistedDns(): List<String> {
        return prefs.getString(DNS_PREFS_KEY, "")
            ?.split(DNS_PREFS_JOIN)
            ?.filter { it.isNotEmpty() }
            ?: emptyList()
    }

    override fun stop() {
        try {
            connectivity?.unregisterNetworkCallback(callback)
        } finally {
            networkInfos.clear()
            updateDns()
        }
    }
}

private const val DNS_PORT = 53

private fun InetAddress.asSocketAddressText(port: Int): String = when (this) {
    is Inet6Address -> "[$hostAddress]:$port"
    is Inet4Address -> "$hostAddress:$port"
    else -> error("Unsupported address type: ${javaClass.name}")
}
