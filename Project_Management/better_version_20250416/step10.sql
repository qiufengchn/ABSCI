-- Drop the existing view if it exists
DROP VIEW IF EXISTS daily_task_details cascade;

-- 创建视图：记录每一天各任务实际的task_status状态及其他工作情况
CREATE OR REPLACE VIEW daily_task_details AS
WITH calculated_efficiency AS (
    SELECT
        dwh.day_number,
        dwh.floor,
        dwh.process,
        dwh.trade AS assigned_trade,
        dwh.planned_remaining,
        dwh.is_valid,
        CASE
          WHEN (
                SELECT MIN(start_day)
                FROM daily_task_record dtr
                WHERE dtr.process = dwh.process
                  AND dtr.floor = dwh.floor
                  AND dtr.day_number <= dwh.day_number
               ) IS NULL
          THEN 'pending'
          WHEN (
                SELECT MIN(complete_day)
                FROM daily_task_record dtr
                WHERE dtr.process = dwh.process
                  AND dtr.floor = dwh.floor
                  AND dtr.complete_day IS NOT NULL
                  AND dtr.day_number <= dwh.day_number
               ) IS NULL
          THEN 'in_progress'
          ELSE 'completed'
        END AS task_status,
        (SELECT initial_production_rate FROM process WHERE process = dwh.process) AS initial_production_rate,
        CASE 
            WHEN (SELECT SUM(daily_work_done) 
                  FROM daily_task_record dtr 
                  WHERE dtr.process = dwh.process 
                    AND dtr.floor = dwh.floor 
                    AND dtr.day_number = dwh.day_number) > dwh.planned_remaining 
            THEN dwh.planned_remaining 
            ELSE (SELECT SUM(daily_work_done) 
                  FROM daily_task_record dtr 
                  WHERE dtr.process = dwh.process 
                    AND dtr.floor = dwh.floor 
                    AND dtr.day_number = dwh.day_number) 
        END AS actual_efficiency,
        CASE 
            WHEN dwh.planned_remaining - 
                 COALESCE((SELECT SUM(daily_work_done) 
                           FROM daily_task_record dtr 
                           WHERE dtr.process = dwh.process 
                             AND dtr.floor = dwh.floor 
                             AND dtr.day_number <= dwh.day_number), 0) < 0 
            THEN 0 
            ELSE dwh.planned_remaining - 
                 COALESCE((SELECT SUM(daily_work_done) 
                           FROM daily_task_record dtr 
                           WHERE dtr.process = dwh.process 
                             AND dtr.floor = dwh.floor 
                             AND dtr.day_number <= dwh.day_number), 0)
        END AS remain_work,
        -- 新增的列：前置工作
        (SELECT STRING_AGG(dependency.predecessor_process, ', ')
         FROM dependency
         WHERE dependency.successor_process = dwh.process) AS predecessor_processes
    FROM daily_work_history dwh
)
SELECT
    calculated_efficiency.day_number,
    calculated_efficiency.floor,
    calculated_efficiency.process,
    calculated_efficiency.assigned_trade,
    calculated_efficiency.planned_remaining,
    calculated_efficiency.is_valid,
    calculated_efficiency.task_status,
    calculated_efficiency.initial_production_rate,
    calculated_efficiency.actual_efficiency,
    calculated_efficiency.remain_work,
    CASE 
        WHEN calculated_efficiency.actual_efficiency = 0 THEN TRUE
        WHEN calculated_efficiency.actual_efficiency IS NULL THEN NULL
        ELSE FALSE
    END AS is_rework,
    LAG(calculated_efficiency.remain_work) OVER (PARTITION BY calculated_efficiency.floor, calculated_efficiency.process ORDER BY calculated_efficiency.day_number) - calculated_efficiency.remain_work AS today_workload,
    calculated_efficiency.predecessor_processes
FROM calculated_efficiency
ORDER BY day_number, process, floor;

SELECT * FROM daily_task_details;