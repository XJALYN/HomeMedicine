# 家药管家 / Home Medicine

一款面向家庭的 iOS 药箱管理应用：录入药品、追踪有效期、设置服药提醒，并支持 iCloud 同步与家庭共享。

**项目主页**：[https://xjalyn.github.io/HomeMedicine/](https://xjalyn.github.io/HomeMedicine/)

[![Website](https://img.shields.io/badge/website-项目主页-0fba82)](https://xjalyn.github.io/HomeMedicine/)
[![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-blue)](ios/HomeMedicine/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](ios/HomeMedicine/)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-green)](ios/HomeMedicine/HomeMedicine/Views/)

## 演示视频

<video src="宣传视频.mp4" controls width="100%" style="max-width: 390px; border-radius: 12px;">
  您的浏览器不支持视频播放，请<a href="宣传视频.mp4">下载演示视频</a>观看。
</video>

## 功能概览

| 模块 | 说明 |
|------|------|
| **药品库** | 搜索、状态筛选（正常 / 临期 / 过期）、详情查看 |
| **添加药品** | 条码扫描、药盒六面 AI 识别、OCR 辅助录入有效期 |
| **用药提醒** | 今日服药时间轴、确认服用、临期预警、本地推送通知 |
| **我的** | 语言切换（26 种语言）、家庭成员、过期清理、订阅管理 |
| **云同步** | SwiftData + CloudKit 私有库同步；家庭版支持 CKShare 共享药箱 |
| **订阅** | 免费版 + Pro / 家庭版（StoreKit 2） |

## 技术栈

- **UI**：SwiftUI（固定浅色主题）
- **持久化**：SwiftData（Medicine、Reminder、Member 等模型）
- **云同步**：CloudKit（容器 `iCloud.com.homemedicine.app`）
- **AI 识别**：阿里云百炼 DashScope（`qwen3-vl-flash` 视觉模型）
- **条码查询**：内置离线 `medicine_barcodes.json` 数据库
- **国际化**：26 个 `.lproj` 语言包

## 环境要求

- macOS + **Xcode 15+**（已在 Xcode 26.3 上验证）
- **iOS 17.0+** 部署目标
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（可选，用于从 `project.yml` 重新生成工程）

## 快速开始

### 1. 克隆仓库

```bash
git clone https://github.com/YOUR_USERNAME/home-medicine.git
cd home-medicine
```

### 2. 配置 API 密钥（AI 药盒识别）

> **重要：请勿将真实密钥提交到 Git。**

AI 识别功能需要 [阿里云百炼 / DashScope](https://help.aliyun.com/zh/model-studio/) 的 API Key。

```bash
cp ios/HomeMedicine/HomeMedicine/Resources/BailianConfig.example.plist \
   ios/HomeMedicine/HomeMedicine/Resources/BailianConfig.plist
```

编辑 `BailianConfig.plist`，将 `YOUR_DASHSCOPE_API_KEY` 替换为你的密钥：

```xml
<key>DASHSCOPE_API_KEY</key>
<string>YOUR_DASHSCOPE_API_KEY</string>
```

也可通过 Xcode Scheme 环境变量注入（不写入文件）：

| 变量名 | 说明 |
|--------|------|
| `DASHSCOPE_API_KEY` | DashScope API Key |

未配置密钥时，应用仍可正常使用；仅 **AI 药盒识别** 功能会提示「未配置识别服务 API 密钥」。

### 3. 配置代码签名

在 Xcode 中打开工程，将 **Development Team** 改为你自己的 Apple Developer 团队：

```bash
open ios/HomeMedicine/HomeMedicine.xcodeproj
```

> 仓库中的 `project.yml` 含示例 Team ID，开源使用前请替换为你自己的团队。

### 4. 构建与运行

选择 iPhone 模拟器或真机，按 **⌘R** 运行。

命令行构建：

```bash
cd ios/HomeMedicine
xcodebuild -scheme HomeMedicine \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

更详细的构建、测试、CloudKit 配置与本地化流程见 **[ios/README.md](ios/README.md)**。

## 项目结构

```
家药管家/
├── README.md                 # 本文件
├── ios/
│   ├── README.md             # iOS 开发详细文档
│   └── HomeMedicine/
│       ├── HomeMedicine.xcodeproj
│       ├── project.yml
│       ├── HomeMedicine/     # 应用源码
│       │   ├── App/
│       │   ├── Models/
│       │   ├── Services/
│       │   ├── Views/
│       │   ├── Theme/
│       │   └── Resources/
│       ├── HomeMedicineTests/
│       ├── HomeMedicineUITests/
│       └── Scripts/          # 本地化、条码库生成脚本
└── project.json              # 产品设计原型元数据（非运行时依赖）
```

## 开发与贡献

### 添加 UI 文案

1. 在 `ios/HomeMedicine/Scripts/generate_localizations.py` 的 `STRINGS` 中添加英文 key
2. 在 `ZH_HANS`（及 `ZH_HANT`）中补充中文
3. 运行全量翻译：

```bash
cd ios/HomeMedicine
python3 Scripts/generate_localizations.py --full-translate
```

### 运行测试

```bash
cd ios/HomeMedicine
xcodebuild test -scheme HomeMedicine \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:HomeMedicineTests
```

欢迎通过 Issue 和 Pull Request 参与贡献。

## 作者

<table>
  <tr>
    <td width="200" align="center">
      <img src="作者抖音.jpg" alt="作者抖音二维码" width="180">
    </td>
    <td>
      <strong>@开发1000个应用</strong><br><br>
      抖音号：<code>KZTY52</code><br><br>
      ❤️ 用编程治愈妄想症，亲手做出 1000 APP<br><br>
      扫码关注抖音，获取更多独立开发与项目更新。
    </td>
  </tr>
</table>

## 安全与隐私

- **API 密钥**：`BailianConfig.plist` 已加入 `.gitignore`，仓库仅提供 `BailianConfig.example.plist` 模板
- **用户数据**：药品与提醒数据默认存储在本地 SwiftData，可选通过 iCloud 同步；不上传至第三方服务器（AI 识别时仅发送用户拍摄的药盒图片至 DashScope）
- **若密钥曾意外提交**：请立即在 [DashScope 控制台](https://dashscope.console.aliyun.com/) 轮换密钥，并考虑使用 `git filter-repo` 清理历史记录

## 许可证

本项目采用 [Apache License 2.0](LICENSE) 开源。

## 免责声明

本应用仅供家庭药品库存管理参考，**不构成医疗建议**。用药请遵医嘱，过期药品请按当地规定处置。
