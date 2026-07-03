import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Profile.update label fallback', () {
    test(
      'uses profile-title before url host and avoids raw id fallback',
      () async {
        final profile = Profile.normal(
          url: 'https://example.com/api/v1/client/subscribe?token=abc',
        );
        final response = Response<List<int>>(
          requestOptions: RequestOptions(path: profile.url),
          data: const [],
          statusCode: 200,
          headers: Headers.fromMap({
            'profile-title': ['Airport Name'],
          }),
        );

        final next = profile.copyWith(
          label: profile.label.takeFirstValid([
            response.headers.value('profile-title'),
            utils.getFileNameForDisposition(
              response.headers.value('content-disposition'),
            ),
            Uri.parse(profile.url).host,
            profile.id.toString(),
          ]),
        );

        expect(next.label, 'Airport Name');
        expect(next.label, isNot(profile.id.toString()));
      },
    );

    test('uses url host when response lacks naming headers', () {
      final profile = Profile.normal(
        url: 'https://sub.example.com/api/v1/client/subscribe?token=abc',
      );

      final next = profile.copyWith(
        label: profile.label.takeFirstValid([
          null,
          null,
          Uri.parse(profile.url).host,
          profile.id.toString(),
        ]),
      );

      expect(next.label, 'sub.example.com');
      expect(next.label, isNot(profile.id.toString()));
    });
  });
}
