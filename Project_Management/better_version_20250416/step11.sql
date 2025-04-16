-- 最后结果

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
    calculated_efficiency.predecessor_processes,
    -- 前置工作在当天同楼层的剩余工作量
    (
        SELECT STRING_AGG(CAST(prev_day_remain.remain_work AS VARCHAR), ', ')
        FROM dependency d
        LEFT JOIN calculated_efficiency prev_day_remain ON 
            d.predecessor_process = prev_day_remain.process AND
            prev_day_remain.floor = calculated_efficiency.floor AND
            prev_day_remain.day_number = calculated_efficiency.day_number
        WHERE d.successor_process = calculated_efficiency.process
    ) AS pre_remain_work,
    
    -- 当前工种是否空闲（1为空闲，0为非空闲）
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM daily_task_record dtr
            WHERE dtr.day_number = calculated_efficiency.day_number
              AND dtr.trade = calculated_efficiency.assigned_trade
              AND dtr.start_day IS NOT NULL 
              AND dtr.complete_day IS NULL
        ) THEN 0  -- 工种正在进行某项任务
        ELSE 1    -- 工种空闲
    END AS trade_available,
    
    -- 检查所有前置工序的剩余工作量是否为0
    CASE
        -- 如果没有前置工序，返回TRUE
        WHEN NOT EXISTS (
            SELECT 1 FROM dependency d WHERE d.successor_process = calculated_efficiency.process
        ) THEN TRUE
        -- 如果有前置工序，检查所有前置工序的剩余工作量是否为0
        ELSE (
            SELECT BOOL_AND(
                COALESCE(
                    (
                        SELECT prev_remain.remain_work = 0
                        FROM calculated_efficiency prev_remain
                        WHERE prev_remain.process = d.predecessor_process
                          AND prev_remain.floor = calculated_efficiency.floor
                          AND prev_remain.day_number = calculated_efficiency.day_number
                    ), 
                    FALSE
                )
            )
            FROM dependency d
            WHERE d.successor_process = calculated_efficiency.process
        )
    END AS prerequisites_completed,
    
    -- 当天该工序是否可以开工
    CASE
        -- 如果工序已完成或正在进行中，则不能开工
        WHEN calculated_efficiency.task_status IN ('completed', 'in_progress') THEN FALSE
        ELSE (
            -- 检查是否满足以下所有条件：
            -- 1. 工种空闲
            -- 2. 所有前置工序已完成（剩余工作量为0）
            (NOT EXISTS (
                SELECT 1
                FROM daily_task_record dtr
                WHERE dtr.day_number = calculated_efficiency.day_number
                  AND dtr.trade = calculated_efficiency.assigned_trade
                  AND dtr.start_day IS NOT NULL 
                  AND dtr.complete_day IS NULL
            )) AND (
                -- 如果没有前置工序，默认可以开始
                NOT EXISTS (
                    SELECT 1 FROM dependency d WHERE d.successor_process = calculated_efficiency.process
                ) OR (
                    -- 如果有前置工序，所有前置工序的剩余工作量必须为0
                    SELECT BOOL_AND(
                        COALESCE(
                            (
                                SELECT prev_remain.remain_work = 0
                                FROM calculated_efficiency prev_remain
                                WHERE prev_remain.process = d.predecessor_process
                                  AND prev_remain.floor = calculated_efficiency.floor
                                  AND prev_remain.day_number = calculated_efficiency.day_number
                            ), 
                            FALSE
                        )
                    )
                    FROM dependency d
                    WHERE d.successor_process = calculated_efficiency.process
                )
            )
        )
    END AS can_start
FROM calculated_efficiency
ORDER BY day_number, process, floor;

SELECT * FROM daily_task_details;