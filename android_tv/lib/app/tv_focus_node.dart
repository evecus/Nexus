import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Reactive FocusNode for TV remote navigation
class TvFocusNode extends FocusNode {
  final isFocused = false.obs;

  TvFocusNode({bool autofocus = false}) {
    isFocused.value = hasFocus;
    addListener(_update);
  }

  void _update() => isFocused.value = hasFocus;

  @override
  void dispose() {
    removeListener(_update);
    super.dispose();
  }
}
