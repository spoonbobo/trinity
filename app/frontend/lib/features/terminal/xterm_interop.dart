import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as js_util;

/// Thin Dart wrapper around the xterm.js Terminal + FitAddon loaded from CDN.
class XtermJs {
  late final js.JsObject _terminal;
  late final js.JsObject _fitAddon;
  js.JsFunction? _onDataDisposable;

  XtermJs({
    int cols = 80,
    int rows = 24,
    String fontFamily = 'JetBrains Mono, IBM Plex Mono, monospace',
    double fontSize = 13,
    String theme = 'dark',
  }) {
    final options = js_util.jsify({
      'cols': cols,
      'rows': rows,
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'cursorBlink': true,
      'allowProposedApi': true,
      'theme': theme == 'dark'
          ? {
              'background': '#0A0A0A',
              'foreground': '#E5E5E5',
              'cursor': '#6EE7B7',
              'cursorAccent': '#0A0A0A',
              'selectionBackground': '#6EE7B744',
              'black': '#0A0A0A',
              'red': '#EF4444',
              'green': '#6EE7B7',
              'yellow': '#FBBF24',
              'blue': '#3B82F6',
              'magenta': '#A78BFA',
              'cyan': '#22D3EE',
              'white': '#E5E5E5',
              'brightBlack': '#6B6B6B',
              'brightRed': '#FCA5A5',
              'brightGreen': '#A7F3D0',
              'brightYellow': '#FDE68A',
              'brightBlue': '#93C5FD',
              'brightMagenta': '#C4B5FD',
              'brightCyan': '#67E8F9',
              'brightWhite': '#FFFFFF',
            }
          : {
              'background': '#F5F5F5',
              'foreground': '#1A1A1A',
              'cursor': '#059669',
              'cursorAccent': '#F5F5F5',
              'selectionBackground': '#05966944',
            },
    });

    final terminalClass = js.context['Terminal'] as js.JsFunction;
    _terminal = js.JsObject(terminalClass, [options]);

    final fitClass = js.context['FitAddon']?['FitAddon'] as js.JsFunction;
    _fitAddon = js.JsObject(fitClass, []);
    _terminal.callMethod('loadAddon', [_fitAddon]);
  }

  void open(html.Element container) {
    _terminal.callMethod('open', [container]);
    fit();
  }

  void write(String data) {
    _terminal.callMethod('write', [data]);
  }

  void fit() {
    _fitAddon.callMethod('fit', []);
  }

  int get cols => _terminal['cols'] as int? ?? 80;
  int get rows => _terminal['rows'] as int? ?? 24;

  /// Register a callback for user input (keystrokes).
  void onData(void Function(String data) callback) {
    _onDataDisposable = js.JsFunction.withThis((_, String data) {
      callback(data);
    });
    _terminal.callMethod('onData', [
      js.JsFunction.withThis((thisArg, String data) {
        callback(data);
      }),
    ]);
  }

  void focus() {
    _terminal.callMethod('focus', []);
  }

  void dispose() {
    _onDataDisposable = null;
    _terminal.callMethod('dispose', []);
  }
}
