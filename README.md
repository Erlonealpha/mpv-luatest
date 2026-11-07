# mpv-test

从 elxosc 离线测试流程抽出的独立 LuaJIT 测试框架，MIT 许可。运行器、断言和
`mp` 桩均无第三方依赖，不需要安装 mpv，也不依赖 elxosc 或 elxlib。
将整个目录复制到其他项目或单独克隆即可使用。目录没有 `main.lua`，不会被
mpv 的目录脚本加载器启动。

## 在其他项目使用

从目标项目根目录执行，测试默认放在 `test/`，代码模块默认从项目根目录加载：

```sh
luajit /path/to/mpv-test/run.lua
luajit /path/to/mpv-test/run.lua -v player/layout
```

测试文件使用以下接口；现有同名 helper 文件也会由独立框架替代，无需改写测试：

```lua
local F = require 'framework'
local mp_stub = require 'mp_stub'
local mp = mp_stub.install()
local script = require 'my_script' -- 安装 stub 后再加载依赖 mp 的模块

F.section('my script')
F.test('uses the host clock', function()
    mp_stub.reset()
    mp_stub.fake.time = 2.5
    F.eq(mp.get_time(), 2.5, 'deterministic time')
end)
```

从任意工作目录运行其他项目，或使用不同测试、代码目录：

```sh
luajit /path/to/mpv-test/run.lua --root /path/to/project --test-dir tests --path src --path vendor
```

`--test-dir`、每个 `--path` 和 `--bootstrap` 都相对于 `--root`；也接受绝对路径。
`--root` 默认当前工作目录，不是框架目录。带空格的路径需要 shell 引号。
`--bootstrap setup.lua` 在测试发现前执行指定 Lua 文件，以项目根目录和测试目录
作为 `...` 的两个参数；可在其中配置 globals、路径或预先安装桩。配置失败立即退出。
运行器本身不会自动安装 `mp`，宿主依赖必须显式调用 `mp_stub.install()`。

自动发现根层 `test_*.lua`，并递归进入以 `test` 开头的分组目录；`real_host/` 和
`fixtures/` 等目录不进入离线测试。文件按相对路径排序。筛选器按路径分段进行
字面子串匹配，可省略 `test_` 和 `.lua`，并支持 Windows 分隔符。
默认输出失败和总结；`-v` 显示文件、section 和成功用例，`-h` 显示帮助。
成功退出码为 0；断言、文件加载、参数、引导或空匹配失败均为 1。

## 接口与边界

`require 'mpv_test.framework'`、`require 'mpv_test.runner'`、
`require 'mpv_test.mp_stub'` 是规范模块名。CLI 同时绑定 `framework`、`runner`、
`mp_stub` 到同一模块对象，让已有测试继续运行。项目自己的测试辅助模块仍从
测试目录加载；不会加载项目旧 `run.lua` 或 `support.lua`。

断言接口保持 `section`、`test`、`ok`、`eq`、`contains`、`close`、`raises`、`fail`、
`results`、`summary`；`close` 默认容差 `1e-9`，`raises` 按异常文本子串匹配。
`file` 和 `set_verbose` 管理报告上下文。统计以断言数计，同一进程累积。

`mp_stub.fake` 是稳定的状态表，`reset()` 替换其内部集合并恢复默认时间、分辨率
和帧率；捕获过 `mp` 的宿主模块仍访问这张表。`install()` 每次提供新的 API 表并
设置 `package.loaded['mp']`。`pump()` 只运行本批未取消的 timeout，执行中新增的
timeout 留到下一次；它按队列模拟帧，不模拟 timeout 的真实延迟。

| 桩 API | 控制和记录 |
| --- | --- |
| `get_time`、`get_osd_size`、display-fps 数值属性 | `fake.time`、`osd_width/height`、`fps` |
| native 属性、mouse-pos、设置属性 | `fake.native_props`、`mouse`、`props` |
| `commandv`、`msg.info/warn/error` | `fake.commands`、`messages` |
| property observer 注册与解除 | `fake.events`、`unobserved`；显式调用 `cb` 驱动事件 |
| script message 和 event 注册/解除 | `fake.log[name]`、`fake.log['event:' .. name]` |
| `add_timeout`、timer `kill` | `fake.timeouts`、`pump()` |
| OSD overlay 创建、update、remove | `fake.overlays`、最新 `overlay`、更新和删除次数 |
| key binding section、enable/disable、mouse area | 各 section 映射与顺序记录 |

这些是原流程覆盖的 API 子集；没有真实 libass、IPC、异步命令、`mp.utils` 或
`mp.assdraw` 实现。未配置的 native 属性保持原桩的 `'native:' .. name` 回退值；
数值属性只支持 display-fps/estimated-display-fps。需要额外 API 时测试可显式替换
已安装的 `mp` 表字段。

`mp_stub.configure({ input_section = 'my-input', preserve_mouse = true })` 可设置
`fake.bindings` 的主 section 视图和旧流程的鼠标保留行为。默认所有 section 都记录，
`bindings` 指向最近一次设置，`reset()` 清空鼠标；`configure()` 恢复默认配置。
配置值会被复制，不修改或持有调用方 options。其他集合在每次 reset 中清空。

## 运行现有 elxosc 测试

从 elxosc 根目录执行；现有 `test/` 无需修改：

```sh
luajit mpv-test/run.lua --path .. --path ../elxlib --bootstrap mpv-test/adapters/elxosc.lua
luajit mpv-test/run.lua --path .. --path ../elxlib --bootstrap mpv-test/adapters/elxosc.lua host_app -v
```

适配文件只提供 `debug_msg`、主 input section 和旧桩的鼠标保留契约。
`--path` 从旁边的 elxlib 直接加载 Lua 源码，绕过其 native `init.lua`；框架本身
不写死此依赖。当前工作区的运行结果及新旧入口对照见 [VALIDATION.md](VALIDATION.md)。
真实宿主 Python fixture 继续由 elxosc 自己管理。

## 框架自检

从本仓库根目录执行：

```sh
luajit run.lua --test-dir tests
emmylua_check . --warnings-as-errors
uv run --group test python -m pytest -q
```

Python 仅用于运行 CLI 回归测试，可直接使用已有 Python + pytest；通过
`MPV_TEST_LUAJIT` 指定 LuaJIT，默认搜索 PATH。回归把框架复制到独立临时目录，
使用完全无 elxosc 的项目验证迁移、空格路径、发现、筛选、失败恢复和兼容模块 identity。

## 文件归属

| 路径 | 职责 |
| --- | --- |
| `run.lua` | 通用 CLI 和 suite 执行 |
| `src/mpv_test/framework.lua` | 断言与报告 |
| `src/mpv_test/runner.lua` | 参数、测试发现与筛选 |
| `src/mpv_test/support.lua` | 通用路径和可选 bootstrap |
| `src/mpv_test/mp_stub.lua` | 离线 mp 桩 |
| `adapters/elxosc.lua` | elxosc 集成设置 |
| `tests/` | 框架自己的 Lua 与 CLI 回归 |

初始来源：elxosc `d465fbe` 的 `test/framework.lua`、`test/runner.lua`、
`test/mp_stub.lua`，按原 MIT 许可证保留版权。项目运行时辅助模块、fixture、
真实宿主流程以及现有测试用例留在原项目。
