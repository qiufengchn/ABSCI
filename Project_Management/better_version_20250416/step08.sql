/*==================================================================
 步骤8：执行模拟
==================================================================*/
-- 使用匿名代码块模拟每日工作，直到所有任务完成或达到n天
DO $$
DECLARE 
    current_day INTEGER := 0;
    max_days INTEGER := 365;  -- 最大模拟天数
BEGIN
    -- 清空历史记录表
    TRUNCATE TABLE daily_work_history;
    TRUNCATE TABLE daily_task_record;
    
    -- 按天循环处理
    WHILE current_day < max_days LOOP
        -- 记录当日状态到历史表
        INSERT INTO daily_work_history (
            day_number, floor, process, trade, 
            planned_remaining, actual_done, is_valid
        )
        SELECT 
            current_day,
            tp.floor,
            tp.process,
            tp.assigned_trade,
            tp.planned_remaining,
            COALESCE(tp.daily_productivity, 0),
            (COALESCE(tp.daily_productivity,0) > 0)
        FROM task_progress tp;
        
        -- 执行当日工作
        PERFORM process_work_day(current_day);
        
        -- 检查是否全部任务完成
        EXIT WHEN NOT EXISTS (
            SELECT 1 FROM task_progress WHERE status != 'completed'
        );
        current_day := current_day + 1;
    END LOOP;
    
    RAISE NOTICE 'Simulation completed in % days', current_day;  -- 输出模拟结果
END $$;