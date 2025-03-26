-- Drop the existing view if it exists
DROP VIEW IF EXISTS daily_task_details;

-- 创建视图：记录每一天各任务实际的task_status状态及其他工作情况
CREATE OR REPLACE VIEW daily_task_details AS
WITH calculated_efficiency AS (
    SELECT
        dwh.day_number,
        dwh.floor,
        dwh.process,
        dwh.trade AS assigned_trade,
        dwh.planned_remaining,
        dwh.actual_done,
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
        dwh.recorded_at,
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
            WHEN dwh.planned_remaining < (SELECT initial_production_rate FROM process WHERE process = dwh.process) 
            THEN (SELECT SUM(daily_work_done) 
                  FROM daily_task_record dtr 
                  WHERE dtr.process = dwh.process 
                    AND dtr.floor = dwh.floor 
                    AND dtr.day_number = dwh.day_number) 
            ELSE (SELECT SUM(daily_work_done) 
                  FROM daily_task_record dtr 
                  WHERE dtr.process = dwh.process 
                    AND dtr.floor = dwh.floor) 
        END AS total_work_done,
        -- 集成更新逻辑
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
        END AS remain_work
    FROM daily_work_history dwh
)
SELECT
    calculated_efficiency.*,
    SUM(CASE WHEN actual_efficiency IS NOT NULL THEN actual_efficiency ELSE 0 END) OVER (PARTITION BY floor, process) AS total_work,
    CASE 
        WHEN actual_efficiency = 0 THEN TRUE
        WHEN actual_efficiency IS NULL THEN NULL
        ELSE FALSE
    END AS is_rework,
    CASE 
        WHEN actual_efficiency = 0 THEN 
            (SELECT daily_productivity 
             FROM task_progress tp 
             WHERE tp.process = calculated_efficiency.process  
               AND tp.floor = calculated_efficiency.floor    
               AND tp.start_day <= calculated_efficiency.day_number 
               AND tp.last_update_day >= calculated_efficiency.day_number)  
        ELSE 0
    END AS invalid_workload_today,
    CASE 
        -- 更新逻辑：确保 updated_actual_efficiency 不小于 0
        WHEN (calculated_efficiency.planned_remaining - COALESCE((SELECT SUM(daily_work_done) 
                                                  FROM daily_task_record dtr 
                                                  WHERE dtr.process = calculated_efficiency.process 
                                                    AND dtr.floor = calculated_efficiency.floor 
                                                    AND dtr.day_number <= calculated_efficiency.day_number), 0)) < 0 
        THEN GREATEST(0, calculated_efficiency.actual_efficiency)  -- Ensure it's not negative
        ELSE calculated_efficiency.actual_efficiency
    END AS updated_actual_efficiency

FROM calculated_efficiency
ORDER BY day_number, process, floor;

SELECT * FROM daily_task_details;