/*==================================================================
 步骤7：扩展处理每日工作的函数（记录每日详细信息）
==================================================================*/
CREATE OR REPLACE FUNCTION process_work_day(current_day INT)
RETURNS void AS $$
DECLARE
    task_rec RECORD;
    work_done INT;          -- 当日实际完成量
    is_invalid BOOLEAN;     -- 是否无效日
    new_remaining INT;      -- 更新后剩余量
    eff NUMERIC(10,2);      -- 效率计算值
    is_rework BOOLEAN;      -- 是否返工
BEGIN
    -- 遍历所有进行中的任务
    FOR task_rec IN (
        SELECT 
            tp.*,
            p.initial_production_rate,
            tr.available_workers
        FROM task_progress tp
        JOIN process p ON tp.process = p.process
        JOIN trade_resource tr ON tp.assigned_trade = tr.trade
        WHERE tp.status = 'in_progress'
    )
    LOOP
        -- 生成10%无效日概率
        is_invalid := (random() < 0.1);
        
        -- 计算实际完成量：无效日为0，否则应用扰动公式
        work_done := CASE 
            WHEN is_invalid THEN 0
            ELSE GREATEST(1, ROUND(task_rec.initial_production_rate * (0.9 + 0.2 * random())) * task_rec.available_workers)
        END;
        
        -- 更新剩余工作量
        new_remaining := CASE 
            WHEN task_rec.remaining_quantity <= work_done THEN 0 
            ELSE task_rec.remaining_quantity - work_done 
        END;
        
        -- 更新任务进度表
        UPDATE task_progress
        SET 
            remaining_quantity = new_remaining,
            last_update_day = current_day,
            daily_productivity = work_done,
            status = CASE 
                        WHEN new_remaining = 0 THEN 'completed'
                        ELSE 'in_progress'
                     END
        WHERE process = task_rec.process AND floor = task_rec.floor;
        
        -- 任务完成时释放工种资源
        IF new_remaining = 0 THEN
            UPDATE trade_resource
            SET status = 'available'
            WHERE trade = task_rec.assigned_trade;
        END IF;
        
        -- 判断返工：任务启动日早于当前日
        is_rework := (task_rec.start_day IS NOT NULL AND task_rec.start_day < current_day);
        
        -- 计算效率百分比
        IF (task_rec.initial_production_rate * task_rec.available_workers) > 0 THEN
            eff := ROUND((work_done::NUMERIC / (task_rec.initial_production_rate * task_rec.available_workers)) * 100, 2);
        ELSE
            eff := 0;
        END IF;
        
        -- 插入每日详细记录
        INSERT INTO daily_task_record (
            day_number, process, floor, trade, 
            is_invalid, is_rework, daily_work_done, efficiency, 
            start_day, complete_day
        ) VALUES (
            current_day,
            task_rec.process,
            task_rec.floor,
            task_rec.assigned_trade,
            is_invalid,
            is_rework,
            work_done,
            eff::TEXT || '%',
            task_rec.start_day,
            CASE WHEN new_remaining = 0 THEN current_day ELSE NULL END
        );
    END LOOP;
    
    -- 启动新任务
    PERFORM update_task_progress(current_day);
END;
$$ LANGUAGE plpgsql;