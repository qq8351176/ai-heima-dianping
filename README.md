# AI 本地生活系统

## 后端接口

```text
GET  /ai/skills
GET  /ai/skills/{code}
POST /ai/skills/{code}/run
GET  /ai/skills/runs
```

AI Skills 的执行流程是固定的：

```text
用户选择 Skill -> 填写表单 -> 后端渲染 prompt_template -> 调用大模型 -> 保存运行记录 -> 返回结果
```

## 使用教程

1. 后端使用 Maven 构建，Spring Boot 版本为 `3.5.6`，JDK 版本为 `17`。
2. 修改 `AI-dianping-backend/src/main/resources/application.yml` 中的 MySQL、Redis 和 `API-KEY` 配置。
3. 执行 `db.sql` 初始化数据库，确保新增的 `tb_ai_skill` 和 `tb_ai_skill_run` 已创建。
4. 后端启动前，在 Redis 中执行：

```text
XGROUP CREATE stream.orders g1 0 MKSTREAM
```

5. 如果需要附近商户 GEO 数据，执行 `AI-dianping-backend/src/test/java/com/hmdp/HmDianPingApplicationTests.java` 中的 `loadShopData`。
6. 前端由 nginx 托管，接口代理到后端 `8081`。

## AI 边界

- 不做 RAG
- 不做 Agent
- 不让 AI 自主选择工具
- 不让 AI 自动预约、发布、发券或修改业务状态
- 所有 AI 输出都作为草稿或建议，由用户确认使用
