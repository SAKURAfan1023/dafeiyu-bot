# Windows Swift 6.1.3 运行库来源

本目录声明随 Windows QQ 包的 `licenses/` 一同分发。Swift 可执行文件和 15 个 DLL 来自已通过 Windows 原生 CI 的 release 产物；Microsoft Visual C++ x64 运行库作为系统前置条件，不从 System32 复制。

| 组件 | 原始许可 | 版本依据 |
| --- | --- | --- |
| Swift、Foundation、libdispatch / BlocksRuntime | 包内 `Swift-LICENSE.txt`，Apache-2.0 with Runtime Library Exception | [Swift 6.1.3](https://github.com/swiftlang/swift/blob/swift-6.1.3-RELEASE/LICENSE.txt)、[libdispatch](https://github.com/swiftlang/swift-corelibs-libdispatch/blob/swift-6.1.3-RELEASE/LICENSE) |
| Foundation ICU / ICU 74.1 | [Foundation 许可](FoundationICU-LICENSE.md)、[Unicode 和 ICU 声明](ICU-74.1-LICENSE.txt) | [对应 Swift 版本的头文件](https://github.com/swiftlang/swift-foundation-icu/blob/swift-6.1.3-RELEASE/icuSources/include/_foundation_unicode/uvernum.h)、[ICU 原文](https://github.com/unicode-org/icu/blob/release-74-1/LICENSE) |
| libcurl 8.9.1 | [COPYING](curl-8.9.1-COPYING.txt) | [curl 原文](https://github.com/curl/curl/blob/curl-8_9_1/COPYING) |
| libxml2 2.11.5 | [Copyright](libxml2-2.11.5-Copyright.txt)、[hash.c / list.c 声明](libxml2-2.11.5-additional-NOTICE.txt) | [原文](https://github.com/GNOME/libxml2/blob/v2.11.5/Copyright)、[hash.c](https://github.com/GNOME/libxml2/blob/v2.11.5/hash.c)、[list.c](https://github.com/GNOME/libxml2/blob/v2.11.5/list.c) |
| zlib 1.3.1 | [LICENSE](zlib-1.3.1-LICENSE.txt) | [zlib 原文](https://github.com/madler/zlib/blob/v1.3.1/LICENSE) |

libcurl、libxml2、zlib 的构建版本和静态链接条件来自 [Swift 6.1.3 Windows 构建脚本](https://github.com/swiftlang/swift/blob/swift-6.1.3-RELEASE/utils/build.ps1)：libcurl 启用 zlib 和 Windows Schannel，关闭 OpenSSL、Brotli、NGHTTP2；libxml2 关闭 zlib、LZMA、iconv。实际 `_FoundationICU.dll` 数据版本为 74，FoundationXML DLL 的构建信息与 libxml2 2.11.5 一致。

Swift Crypto、Swift ASN.1 及 BoringSSL 的 LICENSE / NOTICE 从对应 checkout 收集，与上述文件并存。项目 MIT 不替代这些组件的许可。

ICU 上游许可原始文本 SHA-256（LF 换行）：`17510cf7a58b4879b887ec05a45d72cf1b73544dd9ec7e72f20110ed104229ee`。原文包含公开的版权作者联系地址，保留原文；隐私检查只对这一份固定文件的该类匹配作例外，其他内容变动仍会被检查。
