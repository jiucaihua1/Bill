import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/external_links.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => ExternalLinks.debugOpener = null);

  test('拒绝非 https 地址，不交给浏览器', () async {
    var called = false;
    ExternalLinks.debugOpener = (url) async {
      called = true;
      return true;
    };
    expect(await ExternalLinks.open(Uri.parse('http://example.com')), isFalse);
    expect(await ExternalLinks.open(Uri.parse('intent://example')), isFalse);
    expect(called, isFalse);
  });

  test('浏览器返回失败时归一为 false', () async {
    ExternalLinks.debugOpener = (url) async => false;
    expect(await ExternalLinks.openVerifinRepository(), isFalse);
  });

  test('宿主没有插件实现时不向调用方抛异常', () async {
    // 不注入 opener：测试宿主没有 url_launcher 实现，真实路径会抛
    // MissingPluginException，应由 open 归一为 false。
    expect(await ExternalLinks.openVerifinRepository(), isFalse);
  });
}
