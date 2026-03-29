# ClipSync Git 版本命名规范

这份规则用于统一 `branch`、`commit`、`tag`、`release` 和安装包命名。

## 1. 分支命名

默认主分支：

- `main`

临时开发分支建议：

- `feature/功能名`
- `fix/问题名`
- `chore/杂项名`

示例：

- `feature/auto-import-ui`
- `fix/settings-layout`
- `chore/release-prep`

不建议继续长期使用中文分支名，尤其不要把“正式版”“最终版”这类名称当常驻分支。

## 2. Commit 命名

规则：

- 格式：`类型: 具体改了什么`
- 普通提交写“这次改了什么”
- 发版提交单独写版本号

推荐类型：

- `feat:` 新功能
- `fix:` 修复问题
- `ui:` 界面调整
- `refactor:` 重构
- `docs:` 文档修改
- `chore:` 配置、版本号、杂项
- `release:` 发版提交

示例：

- `feat: support per-device auto import preference`
- `fix: remove extra spacing in remaining capacity tile`
- `ui: refine settings header alignment`
- `docs: update release download links`
- `chore: update version to 1.1.2`
- `release: V1.1.2`

不要再使用这类 commit 名：

- `V1.1.2`
- `最终版`
- `这个版本好了`
- `UI又改了一下`

## 3. Tag 命名

以后只保留一套格式：

- `clipsync_v版本号`

示例：

- `clipsync_v1.0.0`
- `clipsync_v1.1.0`
- `clipsync_v1.1.1`
- `clipsync_v1.1.2`

不要混用以下格式：

- `v1.1.2`
- `V1.1.2`
- `DY-V1.3.0`
- `V2.1.0(z)`

## 4. App 版本号

`Info.plist` 里默认保持一致：

- `CFBundleShortVersionString = 1.1.2`
- `CFBundleVersion = 1.1.2`

如果以后要分内部构建号，再单独调整。

## 5. GitHub Release 命名

发布时统一使用：

- Release 标题：`ClipSync V1.1.2`
- Release Tag：`clipsync_v1.1.2`

## 6. 安装包命名

安装包统一使用：

- `clipsync_v1.1.2.dmg`

源码包统一使用：

- `clipsync_v1.1.2-source.zip`

## 7. 标准发版流程

每次发版按这个顺序走：

1. 更新 `Info.plist` 版本号，例如 `1.1.2`
2. 提交版本号修改：
   `chore: update version to 1.1.2`
3. 提交本次最终功能或 UI 调整
4. 发版提交：
   `release: V1.1.2`
5. 创建 Tag：
   `clipsync_v1.1.2`
6. 生成安装包：
   `clipsync_v1.1.2.dmg`
7. 发布 GitHub Release：
   `ClipSync V1.1.2`

## 8. 一句话规则

- 普通提交写“改了什么”
- 发版提交写 `release: V版本号`
- Tag 只用 `clipsync_v版本号`
- 安装包只用 `clipsync_v版本号.dmg`
