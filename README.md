# Nexus

一个基于 Flutter 的跨平台媒体播放器，支持 Android、Android TV、iOS、macOS、Linux、Windows。

## 目录结构

```
Nexus-master/
├── apps/                    # 各平台专属代码
│   ├── android/             # Android (手机 & 平板)
│   ├── android_tv/          # Android TV
│   ├── ios/                 # iOS
│   ├── macos/                # macOS
│   ├── linux/                # Linux
│   └── windows/              # Windows
├── shared/                  # 跨平台共享代码
│   ├── lib/                 # player_shared 包源码（业务逻辑、Model、State 管理等）
│   └── pubspec.yaml         # player_shared 包定义
└── .github/workflows/       # CI/CD 构建流水线（每个平台一个 workflow）
```

### 各平台目录约定

每个 `apps/<platform>/` 目录只保留：

- `lib/`：该平台的 Dart 源码（UI、平台特定逻辑）
- `pubspec.yaml`：平台专属依赖，并通过 `path: ../../shared` 依赖 `shared/` 下的 `player_shared` 包
- `assets/`：图标等平台专属资源

其中 **`linux`**、**`macos`**、**`windows`** 三个桌面平台的原生 runner（CMake/GTK 工程、Xcode 工程等）**不入库**，由 CI 在构建时通过 `flutter create --platforms=<platform> .` 现场生成。

**`android`**、**`android_tv`**、**`ios`** 三个平台的原生工程（Gradle 工程、Xcode 工程 + 自定义原生插件桥接代码）**随仓库提交**，因为它们包含手动维护的原生代码（如签名配置、自定义原生插件等），不能仅靠 `flutter create` 重新生成。

## 共享代码（`shared/`）

`shared/` 是一个独立的 Dart package（包名 `player_shared`），包含所有平台共用的：

- 业务逻辑与状态管理（基于 `get`）
- 数据模型与本地存储（`hive`）
- 网络请求（`dio`）
- 播放内核封装（`media_kit`）
- 视频缩略图生成、系统交互（亮度/音量/唤醒锁等）跨平台抽象

各平台 app 通过在自己的 `pubspec.yaml` 中声明：

```yaml
dependencies:
  player_shared:
    path: ../../shared
```

来引用这份共享代码，并在其之上实现各自平台特定的 UI 与原生交互。

## 本地开发

### 环境要求

- Flutter SDK `3.44.6`（stable channel）
- Dart SDK `>=3.0.5 <4.0.0`

### 运行指定平台

以 Android 为例：

```bash
cd apps/android
flutter pub get
flutter run
```

其余平台同理，进入对应的 `apps/<platform>` 目录后执行 `flutter pub get` / `flutter run`。

首次拉取依赖时，Flutter 会自动解析 `path: ../../shared` 依赖并一并处理 `shared/` 下的共享包，无需单独在 `shared/` 目录执行 `pub get`（但 CI 中仍会显式执行一次以确保缓存命中，见下文）。

### 桌面平台（Linux / macOS / Windows）

本地开发桌面平台前，需要先生成原生 runner（仓库中未提交）：

```bash
cd apps/linux      # 或 apps/macos、apps/windows
flutter create --platforms=linux .   # 平台名对应替换
flutter pub get
flutter run -d linux                 # 平台名对应替换
```

## CI/CD

`.github/workflows/` 下每个平台一个独立的 `workflow_dispatch` 触发的构建流水线：

| Workflow | 平台 | 产物 |
|---|---|---|
| `android.yml` | Android | 分架构 APK（arm64-v8a / armeabi-v7a） |
| `android_tv.yml` | Android TV | 分架构 APK |
| `ios.yml` | iOS | 未签名 IPA |
| `linux.yml` | Linux | `.deb` + `.zip` |
| `macos.yml` | macOS | ad-hoc 签名的 `.zip`（内含 `.app`） |
| `windows.yml` | Windows | `.zip`（已裁剪 VLC 无用插件） |

所有 workflow 均遵循相同的依赖获取顺序：

```yaml
- name: Get shared package dependencies
  working-directory: shared
  run: flutter pub get

- name: Get <Platform> app dependencies
  working-directory: apps/<platform>
  run: flutter pub get
```

即先在 `shared/` 解析共享包依赖，再在对应 `apps/<platform>/` 下解析平台专属依赖。

## 新增/修改共享逻辑

若修改的内容需要被多个平台复用，应放在 `shared/lib/` 中；若是某平台专属的 UI 或原生交互，则放在对应 `apps/<platform>/lib/` 中。修改 `shared/lib/` 后，各平台无需额外操作即可在下次 `flutter pub get` / `flutter run` 时拿到最新代码（本地路径依赖，非发布到 pub.dev 的版本化依赖）。
