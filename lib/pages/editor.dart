import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

typedef EditingValueChangeBuilder = Widget Function(CodeLineEditingValue value);
typedef TextEditingValueChangeBuilder = Widget Function(TextEditingValue value);

class EditorPage extends ConsumerStatefulWidget {
  final String title;
  final String? content;
  final List<Language> languages;
  final bool supportRemoteDownload;
  final bool titleEditable;
  final Function(BuildContext context, String title, String content)? onSave;
  final Future<bool> Function(
    BuildContext context,
    String title,
    String content,
  )?
  onPop;

  const EditorPage({
    super.key,
    required this.title,
    required this.content,
    this.titleEditable = false,
    this.onSave,
    this.onPop,
    this.supportRemoteDownload = false,
    this.languages = const [Language.yaml],
  });

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  late CodeLineEditingController _controller;
  late CodeFindController _findController;
  late TextEditingController _titleController;
  late FocusNode _focusNode;
  late bool readOnly = false;
  late bool _wordWrap = false;
  CodeChunkController? _chunkController;
  late final SelectionToolbarController _toolbarController;

  @override
  void initState() {
    super.initState();
    readOnly = widget.onSave == null;
    _toolbarController = ContextMenuControllerImpl(readOnly);
    _focusNode = FocusNode();
    _controller = CodeLineEditingController.fromText(widget.content);
    _findController = CodeFindController(_controller);
    _titleController = TextEditingController(text: widget.title);
    if (system.isDesktop) {
      return;
    }
    _focusNode.onKeyEvent = ((_, event) {
      final keys = HardwareKeyboard.instance.logicalKeysPressed;
      final key = event.logicalKey;
      if (!keys.contains(key)) {
        return KeyEventResult.ignored;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _controller.moveCursor(AxisDirection.up);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowDown) {
        _controller.moveCursor(AxisDirection.down);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        _controller.selection.endIndex;
        _controller.moveCursor(AxisDirection.left);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowRight) {
        _controller.moveCursor(AxisDirection.right);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    });
  }

  @override
  void didUpdateWidget(covariant oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final content = widget.content;
      if (content != null && oldWidget.content != content) {
        _controller.text = content;
        _controller.clearHistory();
      }
    });
  }

  @override
  void dispose() {
    _toolbarController.hide(context);
    _findController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Widget _wrapController(EditingValueChangeBuilder builder) {
    return ValueListenableBuilder(
      valueListenable: _controller,
      builder: (_, value, _) {
        return builder(value);
      },
    );
  }

  Widget _wrapTitleController(TextEditingValueChangeBuilder builder) {
    return ValueListenableBuilder(
      valueListenable: _titleController,
      builder: (_, value, _) {
        return builder(value);
      },
    );
  }

  void _handleSearch() {
    _findController.findMode();
  }

  void _handleReplace() {
    _findController.replaceMode();
  }

  void _handleReplaceNext() {
    _findController.replaceMatch();
  }

  void _handleReplaceAll() {
    _findController.replaceAllMatches();
  }

  void _toggleWordWrap() {
    setState(() {
      _wordWrap = !_wordWrap;
    });
  }

  void _handleSave() {
    if (widget.onSave != null) {
      widget.onSave!(
        context,
        _titleController.text,
        _controller.text,
      );
    }
  }

  void _handleCollapseAll() {
    final controller = _chunkController;
    if (controller == null) return;
    final chunks = List<CodeChunk>.of(controller.value);
    for (int i = chunks.length - 1; i >= 0; i--) {
      final chunk = chunks[i];
      if (chunk.canCollapse) {
        controller.collapse(chunk.index);
      }
    }
  }

  void _handleExpandAll() {
    final controller = _chunkController;
    if (controller == null) return;
    final codeLines = _controller.codeLines;
    final indexes = <int>[];
    for (int i = 0; i < codeLines.length; i++) {
      if (codeLines[i].chunkParent) {
        indexes.add(i);
      }
    }
    for (int i = indexes.length - 1; i >= 0; i--) {
      controller.expand(indexes[i]);
    }
  }

  Future<void> _handleImportFormFile() async {
    final file = await picker.pickerFile();
    if (file == null) {
      return;
    }
    final res = utf8.decode(await file.readBytes());
    _controller.text = res;
  }

  Future<void> _handleImportFormUrl() async {
    final appLocalizations = context.appLocalizations;
    final url = await globalState.showCommonDialog(
      child: InputDialog(
        title: appLocalizations.import,
        value: '',
        labelText: appLocalizations.url,
        inputFormatters: TextInputLimits.limit(TextInputLimits.url),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return appLocalizations.emptyTip(appLocalizations.value);
          }
          if (!value.isUrl) {
            return appLocalizations.urlTip(appLocalizations.value);
          }
          return null;
        },
      ),
    );
    if (url == null) {
      return;
    }
    final res = await request.getTextResponseForUrl(url);
    _controller.text = res.data ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final isMobileView = ref.watch(isMobileViewProvider);
    return CommonPopScope(
      onPop: (context) async {
        if (widget.onPop == null) {
          return true;
        }
        final res = await widget.onPop!(
          context,
          _titleController.text,
          _controller.text,
        );
        if (res && context.mounted) {
          return true;
        }
        return false;
      },
      child: CommonScaffold(
        appBar: AppBar(
          title: TextField(
            maxLength: 20,
            enabled: widget.titleEditable,
            controller: _titleController,
            decoration: InputDecoration(
              border: const NoInputBorder(),
              counter: const SizedBox(),
              hintText: appLocalizations.unnamed,
            ),
            style: context.textTheme.titleLarge,
            autofocus: false,
          ),
          actions: genActions([
            if (!readOnly)
              _wrapController(
                (value) => _wrapTitleController(
                  (value) => IconButton(
                    onPressed:
                        _controller.text != widget.content ||
                            _titleController.text != widget.title
                        ? () {
                            widget.onSave!(
                              context,
                              _titleController.text,
                              _controller.text,
                            );
                          }
                        : null,
                    icon: const Icon(Icons.save),
                  ),
                ),
              ),
            _wrapController(
              (value) => CommonPopupBox(
                targetBuilder: (open) {
                  return IconButton(
                    onPressed: () {
                      final isMobile = ref.read(isMobileViewProvider);
                      open(offset: Offset(0, isMobile ? 0 : 20));
                    },
                    icon: const Icon(Icons.more_vert),
                  );
                },
                popup: CommonPopupMenu(
                  items: [
                    PopupMenuItemData(
                      icon: Icons.search,
                      label: appLocalizations.search,
                      onPressed: _handleSearch,
                    ),
                    if (!readOnly)
                      PopupMenuItemData(
                        icon: Icons.find_replace,
                        label: 'Replace',
                        onPressed: _handleReplace,
                      ),
                    PopupMenuItemData(
                      icon: Icons.undo,
                      label: appLocalizations.undo,
                      onPressed: _controller.canUndo ? _controller.undo : null,
                    ),
                    PopupMenuItemData(
                      icon: Icons.redo,
                      label: appLocalizations.redo,
                      onPressed: _controller.canRedo ? _controller.redo : null,
                    ),
                    PopupMenuItemData(
                      icon: _wordWrap
                          ? Icons.wrap_text
                          : Icons.notes,
                      label: 'Word Wrap',
                      onPressed: _toggleWordWrap,
                    ),
                    PopupMenuItemData(
                      icon: Icons.unfold_less,
                      label: 'Collapse All',
                      onPressed: _handleCollapseAll,
                    ),
                    PopupMenuItemData(
                      icon: Icons.unfold_more,
                      label: 'Expand All',
                      onPressed: _handleExpandAll,
                    ),
                    if (widget.supportRemoteDownload && !readOnly)
                      PopupMenuItemData(
                        icon: Icons.arrow_downward,
                        label: appLocalizations.externalFetch,
                        subItems: [
                          PopupMenuItemData(
                            label: appLocalizations.importUrl,
                            onPressed: _handleImportFormUrl,
                          ),
                          PopupMenuItemData(
                            label: appLocalizations.importFile,
                            onPressed: _handleImportFormFile,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ]),
        ),
        body: Stack(
          children: [
            CodeEditor(
              readOnly: readOnly,
              autofocus: false,
              showCursorWhenReadOnly: false,
              findController: _findController,
              findBuilder: (context, controller, readOnly) => FindPanel(
                controller: controller,
                readOnly: readOnly,
                isMobileView: isMobileView,
              ),
              padding: const EdgeInsets.only(right: 16),
              wordWrap: _wordWrap,
              autocompleteSymbols: true,
              focusNode: _focusNode,
              scrollbarBuilder: (context, child, details) {
                return CommonScrollBar(
                  controller: details.controller,
                  child: child,
                );
              },
              toolbarController: _toolbarController,
              indicatorBuilder:
                  (context, editingController, chunkController, notifier) {
                    _chunkController = chunkController;
                    return Row(
                      children: [
                        DefaultCodeLineNumber(
                          controller: editingController,
                          notifier: notifier,
                        ),
                        DefaultCodeChunkIndicator(
                          width: 20,
                          controller: chunkController,
                          notifier: notifier,
                        ),
                      ],
                    );
                  },
              shortcutsActivatorsBuilder:
                  const DefaultCodeShortcutsActivatorsBuilder(),
              chunkAnalyzer: widget.languages.contains(Language.yaml)
                  ? const YamlChunkAnalyzer()
                  : const DefaultCodeChunkAnalyzer(),
              controller: _controller,
              style: CodeEditorStyle(
                fontSize: context.textTheme.bodyLarge?.fontSize?.ap,
                fontFamily: FontFamily.jetBrainsMono.value,
                codeTheme: CodeHighlightTheme(
                  languages: {
                    if (widget.languages.contains(Language.yaml))
                      'yaml': CodeHighlightThemeMode(mode: langYaml),
                    if (widget.languages.contains(Language.javaScript))
                      'javascript': CodeHighlightThemeMode(
                        mode: langJavascript,
                      ),
                    if (widget.languages.contains(Language.json))
                      'json': CodeHighlightThemeMode(mode: langJson),
                  },
                  theme: Theme.of(context).brightness == Brightness.dark
                      ? atomOneDarkTheme
                      : atomOneLightTheme,
                ),
              ),
            ),
            FadeBox(
              child: widget.content == null
                  ? Container(
                      color: context.colorScheme.surface,
                      alignment: Alignment.center,
                      child: const SizedBox.square(
                        dimension: 200,
                        child: CommonCircleLoading(),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

const double _kDefaultFindPanelHeight = 52;

class FindPanel extends StatelessWidget implements PreferredSizeWidget {
  final CodeFindController controller;
  final bool readOnly;
  final bool isMobileView;

  const FindPanel({
    super.key,
    required this.controller,
    required this.readOnly,
    required this.isMobileView,
  });

  double get _baseHeight =>
      (isMobileView ? _kDefaultFindPanelHeight * 2 : _kDefaultFindPanelHeight) +
      8;

  double get _replaceHeight => _baseHeight + _kDefaultFindPanelHeight + 8;

  @override
  Size get preferredSize {
    if (controller.value == null) {
      return Size.zero;
    }
    final isReplaceMode =
        controller.value!.replaceMode && !readOnly;
    return Size(double.infinity, isReplaceMode ? _replaceHeight : _baseHeight);
  }

  @override
  Widget build(BuildContext context) {
    if (controller.value == null) {
      return const SizedBox(width: 0, height: 0);
    }
    final isReplaceMode =
        controller.value!.replaceMode && !readOnly;
    final height = isReplaceMode ? _replaceHeight : _baseHeight;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 8),
      color: context.colorScheme.surface,
      alignment: Alignment.centerLeft,
      height: height,
      child: _buildFindInputView(context),
    );
  }

  Widget _buildFindInputView(BuildContext context) {
    final CodeFindValue value = controller.value!;
    final isReplaceMode = value.replaceMode && !readOnly;
    final String result;
    if (value.result == null) {
      result = context.appLocalizations.none;
    } else {
      result = '${value.result!.index + 1}/${value.result!.matches.length}';
    }
    final bar = CommonMinIconButtonTheme(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!isMobileView) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: _buildFindInput(context, value),
            ),
            const SizedBox(width: 12),
          ],
          Text(result, style: context.textTheme.bodyMedium),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 2,
              children: [
                _buildIconButton(
                  onPressed: value.result == null
                      ? null
                      : () {
                          controller.previousMatch();
                        },
                  icon: Icons.arrow_upward,
                ),
                _buildIconButton(
                  onPressed: value.result == null
                      ? null
                      : () {
                          controller.nextMatch();
                        },
                  icon: Icons.arrow_downward,
                ),
                const SizedBox(width: 2),
                IconButton.filledTonal(
                  onPressed: controller.close,
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (isReplaceMode) {
      final replaceBar = CommonMinIconButtonTheme(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (!isMobileView) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: _buildReplaceInput(context),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 2,
                children: [
                  _buildIconButton(
                    onPressed: () {
                      controller.replaceMatch();
                    },
                    icon: Icons.check,
                  ),
                  _buildIconButton(
                    onPressed: () {
                      controller.replaceAllMatches();
                    },
                    icon: Icons.done_all,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      if (isMobileView) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            bar,
            const SizedBox(height: 8),
            _buildFindInput(context, value),
            const SizedBox(height: 8),
            replaceBar,
            const SizedBox(height: 4),
            _buildReplaceInput(context),
          ],
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          bar,
          const SizedBox(height: 8),
          replaceBar,
        ],
      );
    }
    if (isMobileView) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          bar,
          const SizedBox(height: 12),
          _buildFindInput(context, value),
        ],
      );
    }
    return bar;
  }

  Widget _buildReplaceInput(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      spacing: 8,
      children: [
        Flexible(
          child: _buildTextField(
            context: context,
            onSubmitted: () {
              controller.replaceMatch();
              controller.replaceInputFocusNode.requestFocus();
            },
            controller: controller.replaceInputController,
            focusNode: controller.replaceInputFocusNode,
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildFindInput(BuildContext context, CodeFindValue value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      spacing: 8,
      children: [
        Flexible(
          child: _buildTextField(
            context: context,
            onSubmitted: () {
              if (value.result == null) {
                return;
              }
              controller.nextMatch();
              controller.findInputFocusNode.requestFocus();
            },
            controller: controller.findInputController,
            focusNode: controller.findInputFocusNode,
          ),
        ),
        _buildCheckText(
          context: context,
          text: 'Aa',
          isSelected: value.option.caseSensitive,
          onPressed: () {
            controller.toggleCaseSensitive();
          },
        ),
        _buildCheckText(
          context: context,
          text: '.*',
          isSelected: value.option.regex,
          onPressed: () {
            controller.toggleRegex();
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required FocusNode focusNode,
    required VoidCallback onSubmitted,
  }) {
    return SizedBox(
      height: globalState.measure.bodyMediumHeight + 8 * 2,
      child: TextField(
        maxLines: 1,
        focusNode: focusNode,
        inputFormatters: TextInputLimits.limit(TextInputLimits.search),
        style: context.textTheme.bodyMedium,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12),
        ),
        onSubmitted: (_) {
          onSubmitted();
        },
        controller: controller,
      ),
    );
  }

  Widget _buildCheckText({
    required BuildContext context,
    required String text,
    required bool isSelected,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 28,
      height: 28,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: isSelected
            ? IconButton.filledTonal(
                onPressed: onPressed,
                padding: const EdgeInsets.all(2),
                icon: Text(text, style: context.textTheme.bodySmall),
              )
            : IconButton(
                onPressed: onPressed,
                padding: const EdgeInsets.all(2),
                icon: Text(text, style: context.textTheme.bodySmall),
              ),
      ),
    );
  }

  Widget _buildIconButton({required IconData icon, VoidCallback? onPressed}) {
    return IconButton(onPressed: onPressed, icon: Icon(icon, size: 16));
  }
}

class ContextMenuControllerImpl implements SelectionToolbarController {
  OverlayEntry? _overlayEntry;
  bool _isFirstRender = true;
  bool readOnly = false;

  ContextMenuControllerImpl(this.readOnly);

  void _removeOverLayEntry() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isFirstRender = true;
  }

  @override
  void hide(BuildContext context) {
    _removeOverLayEntry();
  }

  @override
  void show({
    required context,
    required controller,
    required anchors,
    renderRect,
    required layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    _removeOverLayEntry();
    _overlayEntry ??= OverlayEntry(
      builder: (context) => CodeEditorTapRegion(
        child: ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, _, child) {
            final appLocalizations = context.appLocalizations;
            final isNotEmpty = controller.selectedText.isNotEmpty;
            final isAllSelected = controller.isAllSelected;
            final hasSelected = controller.selectedText.isNotEmpty;
            final List<PopupMenuItemData> menus = [
              if (isNotEmpty)
                PopupMenuItemData(
                  label: appLocalizations.copy,
                  onPressed: controller.copy,
                ),
              if (!readOnly)
                PopupMenuItemData(
                  label: appLocalizations.paste,
                  onPressed: controller.paste,
                ),
              if (isNotEmpty && !readOnly)
                PopupMenuItemData(
                  label: appLocalizations.cut,
                  onPressed: controller.cut,
                ),
              if (hasSelected && !isAllSelected)
                PopupMenuItemData(
                  label: appLocalizations.selectAll,
                  onPressed: controller.selectAll,
                ),
            ];
            if (_isFirstRender) {
              _isFirstRender = false;
            } else if (controller.selectedText.isEmpty) {
              _removeOverLayEntry();
            }
            if (menus.isEmpty) {
              _removeOverLayEntry();
              return const SizedBox();
            }
            return TextSelectionToolbar(
              anchorAbove: anchors.primaryAnchor,
              anchorBelow: anchors.secondaryAnchor ?? Offset.zero,
              children: menus.asMap().entries.map((
                MapEntry<int, PopupMenuItemData> entry,
              ) {
                return TextSelectionToolbarTextButton(
                  padding: TextSelectionToolbarTextButton.getPadding(
                    entry.key,
                    menus.length,
                  ),
                  alignment: AlignmentDirectional.centerStart,
                  onPressed: () {
                    if (entry.value.onPressed == null) {
                      return;
                    }
                    entry.value.onPressed!();
                    _removeOverLayEntry();
                  },
                  child: Text(entry.value.label),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }
}

class _ImportOptionsDialog extends StatefulWidget {
  const _ImportOptionsDialog();

  @override
  State<_ImportOptionsDialog> createState() => _ImportOptionsDialogState();
}

class _ImportOptionsDialogState extends State<_ImportOptionsDialog> {
  void _handleOnTab(ImportOption value) {
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonDialog(
      title: appLocalizations.import,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Wrap(
        children: [
          ListItem(
            onTap: () {
              _handleOnTab(ImportOption.url);
            },
            title: Text(appLocalizations.importUrl),
          ),
          ListItem(
            onTap: () {
              _handleOnTab(ImportOption.file);
            },
            title: Text(appLocalizations.importFile),
          ),
        ],
      ),
    );
  }
}

class YamlChunkAnalyzer implements CodeChunkAnalyzer {
  const YamlChunkAnalyzer();

  @override
  List<CodeChunk> run(CodeLines codeLines) {
    final List<CodeChunk> chunks = [];
    final List<_IndentEntry> stack = [];

    for (int i = 0; i < codeLines.length; i++) {
      final String text = codeLines[i].text;
      final int indent = _getIndent(text);
      if (indent < 0) continue;

      while (stack.isNotEmpty && stack.last.indent >= indent) {
        final entry = stack.removeLast();
        final int end = i - 1;
        if (end > entry.index) {
          chunks.add(CodeChunk(entry.index, end));
        }
      }
      stack.add(_IndentEntry(index: i, indent: indent));
    }

    int lastContentIndex = codeLines.length - 1;
    while (lastContentIndex >= 0 &&
        _getIndent(codeLines[lastContentIndex].text) < 0) {
      lastContentIndex--;
    }
    while (stack.isNotEmpty) {
      final entry = stack.removeLast();
      if (lastContentIndex > entry.index) {
        chunks.add(CodeChunk(entry.index, lastContentIndex));
      }
    }

    chunks.sort((a, b) => a.index - b.index);
    return chunks;
  }

  static int _getIndent(String text) {
    final line = text.trimRight();
    int i = 0;
    while (i < line.length && line[i] == ' ') {
      i++;
    }
    if (i >= line.length || line[i] == '#') {
      return -1;
    }
    return i;
  }
}

class _IndentEntry {
  final int index;
  final int indent;
  const _IndentEntry({required this.index, required this.indent});
}
