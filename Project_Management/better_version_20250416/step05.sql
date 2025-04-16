
/*==================================================================
 步骤5：创建更新任务进度的函数（增加楼层先后顺序判断）
==================================================================*/
-- 函数功能：启动符合条件的新任务（依赖完成、低楼层完成、工种可用）
CREATE OR REPLACE FUNCTION update_task_progress(current_day INT)
RETURNS void AS $$
DECLARE
    task_record RECORD;
    assigned_trades TEXT[] := ARRAY[]::TEXT[];  -- 记录已分配工种，避免重复占用
BEGIN
    -- 查询符合条件的待启动任务（按楼层和工序排序）
    FOR task_record IN (
        SELECT 
            tp.process,
            tp.floor,
            tp.assigned_trade
        FROM task_progress tp
        WHERE tp.status = 'pending'
          -- 检查依赖是否完成（同一楼层）
          AND NOT EXISTS (
              SELECT 1 
              FROM dependency d
              JOIN task_progress tp2 ON d.predecessor_process = tp2.process
              WHERE d.successor_process = tp.process
                AND tp2.floor = tp.floor 
                AND tp2.status != 'completed'
          )
          -- 检查低楼层是否完成（同一工序）
          AND NOT EXISTS (
              SELECT 1
              FROM task_progress lower_tp 
              WHERE lower_tp.process = tp.process
                AND lower_tp.floor < tp.floor
                AND lower_tp.status != 'completed'
          )
          -- 检查工种是否可用
          AND EXISTS (
              SELECT 1 
              FROM trade_resource tr
              WHERE tr.trade = tp.assigned_trade
                AND tr.status = 'available'
          )
        ORDER BY tp.floor, tp.process  -- 按楼层和工序顺序启动
    )
    LOOP
        -- 确保同一工种不同时分配多个任务
        IF NOT task_record.assigned_trade = ANY(assigned_trades) THEN
            -- 更新任务状态为进行中，记录开始时间
            UPDATE task_progress
            SET 
                status = 'in_progress',
                start_day = current_day,
                last_update_day = current_day
            WHERE process = task_record.process
              AND floor = task_record.floor;

            -- 标记工种为忙碌状态
            UPDATE trade_resource
            SET status = 'busy'
            WHERE trade = task_record.assigned_trade;

            assigned_trades := array_append(assigned_trades, task_record.assigned_trade);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;