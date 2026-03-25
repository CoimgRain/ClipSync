# MediaImporterMenuBar

一个 macOS 菜单栏小工具：

- 插入 SD 卡或 U 盘后，显示设备剩余容量
- 选择一个目标文件夹后，可将照片和视频导入进去
- 支持开启“插入后自动导入”

## 运行方式

1. 用 Xcode 打开这个文件夹里的 `Package.swift`
2. 等待 Xcode 加载完成
3. 选择运行目标 `MediaImporterMenuBar`
4. 点击运行

如果你在终端里遇到 `xcodebuild requires Xcode` 之类的提示，先执行：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## 当前行为

- 菜单栏会检测外部可移动存储设备
- 菜单中会显示剩余容量、总容量和容量进度条
- “导入照片和视频”当前使用复制方式，不会删除 U 盘或 SD 卡里的原文件
- 导入目录结构为：`目标文件夹/设备名/时间戳/`

## 支持导入的格式

图片：

`jpg` `jpeg` `png` `heic` `gif` `bmp` `tif` `tiff` `raw` `dng`

视频：

`mp4` `mov` `m4v` `avi` `mts` `m2ts` `mpg` `mpeg` `wmv` `mkv`
