# 初始抽离验证（2026-11-08）

来源为 elxosc `d465fbe`，保留工作区已有 `main.lua` 启用开关变更，现有 `test/`
和生产代码没有修改。新目录独立初始化 Git，父项目不添加 gitlink 或复制测试用例。

## 独立框架

在 `mpv-test/` 中执行：

```text
luajit run.lua --test-dir tests
emmylua_check . --warnings-as-errors
uv run --offline --group test python -m pytest -q
```

Lua 自检 **41 checks passed**；静态检查 **No issues found**；CLI 回归
**28 passed**。CLI 回归使用框架自己的 `pyproject.toml`、锁文件和隔离环境，
并复制运行器到临时目录，对完全独立的项目运行，不借用 elxosc helper。
其中四项 Windows shell 路径边界检查在其他系统按平台 skip。

## 当前 elxosc 测试

在 elxosc 根目录执行：

```text
luajit test/run.lua
luajit mpv-test/run.lua --path .. --path ../elxlib --bootstrap mpv-test/adapters/elxosc.lua
luajit mpv-test/run.lua --path .. --path ../elxlib --bootstrap mpv-test/adapters/elxosc.lua ass_measure
emmylua_check .
uv run --offline --group test python -m pytest -q test/real_host test/test_runner.py test/test_ass_measure_cli.py test/test_benchmark_cli.py --tb=short
```

两个完整 Lua 入口均发现 **37 个测试文件**，结果均为 **1148 passed / 23 failures**，
退出码 1。新旧完整 stdout 保存后逐行对照一致，抽离没有新增失败、隐藏失败或
改变断言报告。ASS 测量筛选 **76 checks passed**；项目静态检查
**No issues found**。

这 23 项失败包括外部 sibling elxlib 的 `elxlibs/std/class.lua:224` 报错
`attempt to index a nil value`，以及由模块加载失败连带产生的
`loop or previous error loading module 'runtime_support'`。这与项目
`dev/design/TESTING.md` 的历史基线不同；本次记录以实际工作区结果为准。
没有修改、patch 或绕过外部 class 实现来让测试变绿。

Python 完整检查 **43 passed / 1 failed**，无 skip：real-host **15 passed / 1 failed**，
旧 runner CLI **14 passed**，测量 CLI **11 passed**，benchmark CLI **3 passed**。
失败项 `test_measure_benchmark_compares_real_bounds_for_all_strategies` 单独以
`--tb=short --showlocals` 复验，仍失败，report.error 明确来自隔离副本中的
同一个 `elxlib/elxlibs/std/class.lua:224`。真实 fixture 保持原来的隔离 config 和
自有进程清理，不加载新框架的 mp 桩。

验证环境：Windows x64；离线 LuaJIT `2.1.1748459687`；宿主
`E:/mpvnet/mpvnet.com`，mpv `v0.41.0-1011-g182fa6ca4`，宿主 LuaJIT
`2.1.1787944725`；Python `3.14.2+freethreaded`。Python 宿主检查设置了
`ELXOSC_MPV_BINARY=E:/mpvnet/mpvnet.com`。uv 使用已有离线缓存；绝对工具路径只作
环境记录，不进入框架配置。

提交前检查 `git diff --check`、独立仓库 staged diff/stat/status，以及父仓库
`git diff --exit-code -- test`。独立仓库包含源码、说明、许可证、回归和锁文件，
不提交虚拟环境、缓存或本机配置。
