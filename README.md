# 四国军棋自动辅助器 iOS 工程

这是一个单机 iPhone 半自动方案，使用官方能力实现：

- ReplayKit Broadcast Upload Extension 读取整机画面
- 录屏扩展通过本机 TCP 把关键帧传给主 App
- 主 App 使用 Vision 做中文 OCR
- 规则引擎维护棋子状态并推算敌方未知棋子
- AVPictureInPictureController 在微信小游戏上方显示情报

iOS 不允许普通 App 自动启动系统录屏。每局开始前需要从控制中心启动一次录屏，之后识别、记牌和推理自动运行。

## 构建方式

1. 将本目录推送到 GitHub 仓库。
2. 打开仓库的 Actions 页面，运行 `build-unsigned-ipa`。
3. 下载 `JunqiAssistant-unsigned-ipa`。
4. 使用爱思助手或其他签名工具导入 IPA 并签名安装。

## 本地构建

需要 macOS 和 Xcode：

```bash
brew install xcodegen
xcodegen generate
open JunqiAssistant.xcodeproj
```

主 App 和录屏扩展必须同时签名。当前工程不使用 App Group，录屏扩展通过 `127.0.0.1:59321` 与主 App 通信，便于免费签名安装。

## 使用流程

1. 打开助手 App，点击“启动辅助”。
2. 确认画中画窗口已出现。
3. 切到微信小游戏。
4. 从控制中心启动系统录屏，选择“军棋助手”。
5. 画中画会显示识别状态和推理情报。

## 已知限制

- 系统录屏必须由用户手动启动。
- 首次加载需要真机验证画中画与录屏扩展是否能同时运行。
- OCR 和棋盘识别需要根据实际界面继续校准。

## 当前版本状态

已完成第一版工程骨架：

- ReplayKit 录屏扩展
- 本机 TCP 帧传输
- Apple Vision 中文 OCR
- 棋子识别与步数解析
- 军棋规则与候选概率引擎
- 画中画情报渲染
- GitHub Actions 未签名 IPA 构建

还需要用真机继续校准棋盘坐标、棋子背面识别和吃子事件追踪。当前版本会先验证录屏、OCR 和画中画链路是否正常。
