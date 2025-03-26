-- 步骤10：创建最终结果展示视图（包含实际工作量、扰动值和效率百分比）
DROP VIEW IF EXISTS public.daily_task_details;

CREATE OR REPLACE VIEW public.daily_task_details AS 
SELECT 
    dwh.day_number AS "Day",
    dwh.floor AS "Floor",
    dwh.process AS "Process",
    p.trade AS "Trade",
    -- 动态计算实际完成量（取剩余量与效率的较小值）
    LEAST(
        dwh.actual_done, 
        tp.remaining_quantity + dwh.actual_done  -- 当天开始前的剩余量
    ) AS "Actual_Work_Done",
    -- 扰动值 = 实际完成量 - 初始效率
    (LEAST(dwh.actual_done, tp.remaining_quantity + dwh.actual_done) - p.initial_production_rate) AS "Efficiency_Perturbation",
    -- 效率百分比 = (实际完成量 / 初始效率) * 100
    ROUND(
        (LEAST(dwh.actual_done, tp.remaining_quantity + dwh.actual_done)::NUMERIC 
        / p.initial_production_rate * 100, 
        2
    ) || '%' AS "Efficiency_Percentage",
    -- 动态任务状态
    CASE
        WHEN tp.status = 'completed' THEN 'completed'
        WHEN tp.status = 'in_progress' THEN 'in_progress'
        ELSE 'pending'
    END AS "Task_Status",
    dwh.recorded_at AS "Recorded_At"
FROM 
    daily_work_history dwh
JOIN process p ON dwh.process = p.process
JOIN task_progress tp ON dwh.process = tp.process AND dwh.floor = tp.floor
ORDER BY 
    dwh.day_number, dwh.process, dwh.floor;

-- 查询最终结果
SELECT * FROM public.daily_task_details;