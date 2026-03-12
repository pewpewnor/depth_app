import 'dart:developer' as developer;
import 'dart:io';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/foundation.dart';

void logAndToast(String message, {String name = 'AppLog'}) {
  developer.log(message, name: name);
  debugPrint('[$name]: $message');
  if (Platform.isAndroid || Platform.isIOS) {
    Fluttertoast.showToast(msg: message);
  }
}
