/*==================================================================
 步骤9：查看结果
==================================================================*/
-- 创建视图：汇总项目进度详情（含工种状态、累计完成量等）
CREATE OR REPLACE VIEW project_progress_details AS
SELECT 
    dwh.day_number AS "Day",
    dwh.floor AS "Floor",
    dwh.process AS "Process",
    p.trade AS "Process Trade",
    r.status AS "Trade Status",
    t.initial_quantity AS "Total Work",
    dwh.planned_remaining AS "Plan Remaining",
    dwh.actual_done AS "Daily Done",
    (t.initial_quantity - dwh.planned_remaining) AS "Cumulative Done",
    CASE WHEN dwh.is_valid THEN 'Valid' ELSE 'Invalid' END AS "Validity",
    ROUND(dwh.actual_done::NUMERIC / p.initial_production_rate * 100) || '%' AS "Efficiency",
    tp.status AS "Task Status"
FROM daily_work_history dwh
JOIN task t USING (process)
JOIN process p USING (process)
JOIN task_progress tp ON dwh.process = tp.process AND dwh.floor = tp.floor
JOIN trade_resource r ON tp.assigned_trade = r.trade;

-- 查询最终任务进度
SELECT * FROM task_progress;

-- 查询每日详细记录（按天、工序、楼层排序）
SELECT * FROM daily_task_record ORDER BY day_number, process, floor;