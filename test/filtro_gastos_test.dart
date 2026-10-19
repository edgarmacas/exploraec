import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:exploraec/controllers/auth_controller.dart';
import 'package:exploraec/controllers/gastos_controller.dart';
import 'package:exploraec/screens/gastos_screen.dart';
import 'package:exploraec/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Servidor falso mínimo (Sesión 10, Paso 7): solo lo que la pantalla Gastos
/// necesita para cargar — token, perfil, categorías y una lista de gastos fija.
/// No necesita el backend ni el emulador.
class _Servidor implements HttpClientAdapter {
  final gastos = <Map<String, dynamic>>[
    {'id': 1, 'descripcion': 'Almuerzo', 'monto': 6.5, 'categoria': 'comida', 'fecha': '2026-10-08'},
    {'id': 2, 'descripcion': 'Taxi', 'monto': 3.25, 'categoria': 'transporte', 'fecha': '2026-10-08'},
    {'id': 3, 'descripcion': 'Cena', 'monto': 9.0, 'categoria': 'comida', 'fecha': '2026-10-08'},
  ];

  ResponseBody _json(Object? cuerpo, int codigo, [Map<String, List<String>> h = const {}]) =>
      ResponseBody.fromString(cuerpo == null ? '' : jsonEncode(cuerpo), codigo,
          headers: {Headers.contentTypeHeader: ['application/json'], ...h});

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? cuerpo, Future<void>? cancelar) async {
    final ruta = o.path;
    if (ruta == '/usuarios/token') {
      return _json({'access_token': 'tok-a@b.com', 'token_type': 'bearer'}, 200);
    }
    if (ruta == '/usuarios/me') {
      return _json({'id': 1, 'email': 'a@b.com'}, 200);
    }
    if (ruta == '/gastos/categorias') {
      return _json({'categorias': ['comida', 'transporte', 'entretenimiento', 'otros'], 'limite_por_categoria': 500.0}, 200);
    }
    if (ruta == '/gastos/' && o.method == 'GET') {
      return _json(gastos, 200, {'x-total-count': ['${gastos.length}']});
    }
    return _json({'detail': 'ruta no prevista en la prueba: $ruta'}, 404);
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _esperar(bool Function() condicion) async {
  for (var i = 0; i < 200 && !condicion(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUpAll(() => Hive.init(Directory.systemTemp.createTempSync('hive_filtro').path));

  testWidgets('Paso 7 — al elegir «comida» solo se ven los gastos de comida', (tester) async {
    // El reloj de testWidgets es falso: la espera real (disco, «red» falsa)
    // va dentro de runAsync, igual que en sesion_09_test.dart.
    await tester.runAsync(() async {
      Get.reset();
      Get.testMode = true;
      await Hive.deleteFromDisk();
      FlutterSecureStorage.setMockInitialValues({});

      final servidor = _Servidor();
      Get.put(ApiClient(dio: Dio(BaseOptions(baseUrl: 'http://prueba'))..httpClientAdapter = servidor));
      final auth = Get.put(AuthController());
      await _esperar(() => !auth.restaurando.value);
      await auth.iniciarSesion('a@b.com', 'clave-1234');

      final g = Get.put(GastosController());
      await _esperar(() => g.estado.value.name == 'exito' && g.gastos.length == 3);
    });

    await tester.pumpWidget(const GetMaterialApp(home: GastosScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Con «Todas» se ven los tres gastos.
    expect(find.text('Almuerzo'), findsOneWidget);
    expect(find.text('Taxi'), findsOneWidget);
    expect(find.text('Cena'), findsOneWidget);

    // Al tocar el chip «comida», desaparecen los de otras categorías.
    await tester.tap(find.widgetWithText(FilterChip, 'comida'));
    await tester.pump();

    expect(find.text('Almuerzo'), findsOneWidget);
    expect(find.text('Cena'), findsOneWidget);
    expect(find.text('Taxi'), findsNothing);

    // Al volver a «Todas» se ven otra vez los tres.
    await tester.tap(find.widgetWithText(FilterChip, 'Todas'));
    await tester.pump();

    expect(find.text('Taxi'), findsOneWidget);
  });
}
