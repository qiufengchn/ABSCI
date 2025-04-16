/*==================================================================
 步骤1：清理环境（每次重新运行前必须执行）
==================================================================*/
-- 删除所有相关表和视图，CASCADE 确保级联删除依赖对象
DROP TABLE IF EXISTS 
    daily_task_record, daily_work_history, task_progress, trade_resource, space, task, 
    dependency, process CASCADE;

DROP VIEW IF EXISTS current_project_status, project_progress_details CASCADE;
