package com.follow.clash.service.models

data class NotificationParams(
    val title: String = "Lclash",
    val stopText: String = "STOP",
    val onlyStatisticsProxy: Boolean = false,
)
