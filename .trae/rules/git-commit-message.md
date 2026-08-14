---
alwaysApply: false
description: about commits
scene: git_message
---

# Git Commit Message 规范

## 格式

```
<type>(<scope>): <subject>

<body>

<footer>
```

type、scope 用英文小写；subject、body 用中文。

## 类型（type）

| 类型     | 说明                       |
| -------- | -------------------------- |
| feat     | 新功能                     |
| fix      | 修复 bug                   |
| refactor | 重构（不改功能也不修 bug） |
| perf     | 性能优化                   |
| style    | 代码格式调整（不影响逻辑） |
| docs     | 文档变更                   |
| test     | 测试相关                   |
| build    | 影响构建系统或外部依赖     |
| deps     | 依赖的增删与版本变更       |
| sec      | 安全漏洞修复               |
| chore    | 其他杂项                   |
| ci       | CI/CD 配置变更             |
| revert   | 回滚                       |
| release  | 发布版本                   |

## 模块（scope）

按项目分层与功能模块取值：

- `core` — 基础工具/常量/配置（如日志、Dio 封装）
- `domain` — 领域模型与仓库接口
- `application` — 用例与业务逻辑
- `data` — 数据源实现（网络/本地存储）
- `presentation` — UI 页面与状态管理（Riverpod）
- `auth` — 登录/认证/会话
- `task` — 任务管理
- `settings` — 设置
- `i18n` — 国际化/本地化
- `platform` — 平台相关（Android/iOS/Windows）
- `config` — 配置文件（pubspec.yaml、环境配置等）

scope 可选，仅在变更涉及特定模块时添加。

## subject

- 中文，简洁描述变更内容，不超过 50 字符
- 首字母不大写，句末不加标点
- 类型和模块仅供参考，可以使用未列出的的类型或模块。

## body

- 中文，说明变更原因与具体内容
- 优先用要点列表说明关键改动，每项一条

## footer

- 破坏性变更：`<type>!` 标记，并在 footer 用 `BREAKING CHANGE: 描述` 说明影响
- 其他说明（如 issue 引用）放在 footer

## 示例

```
feat(auth): 实现登录页面与会话管理

- 新增登录页，支持输入服务器地址、用户名和密码
- 登录成功后持久化 sessionId 与服务器地址
- 密码使用 SHA256 哈希后传输
```

```
fix(task): 修复任务进度轮询在页面切回时重复启动的问题
```

```
refactor!(core): 统一错误处理为 ApiException

BREAKING CHANGE: 移除各模块自定义异常，改用 ApiException 分类
```
