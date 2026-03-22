-- Aseprite Sprite Sheet Splitter Plugin
-- Author: Gemini AI Assistant
-- Description: Split a sprite sheet into individual files based on row and column count.

local spr = app.activeSprite
if not spr then
    return app.alert("No active sprite!")
end

-- Predefined high-contrast colors
local presets = {
    { name="Magenta", color=Color{ r=255, g=0, b=255, a=200 } },
    { name="Cyan",    color=Color{ r=0, g=255, b=255, a=200 } },
    { name="Yellow",  color=Color{ r=255, g=255, b=0, a=200 } },
    { name="Red",     color=Color{ r=255, g=0, b=0, a=200 } },
    { name="Green",   color=Color{ r=0, g=255, b=0, a=200 } },
    { name="White",   color=Color{ r=255, g=255, b=255, a=200 } }
}

local function cleanupPreview()
    if not spr or not spr.layers then return end
    for _, layer in ipairs(spr.layers) do
        if layer.name == "Split Preview" then
            spr:deleteLayer(layer)
            app.refresh()
            break
        end
    end
end

local function updateTargetN(dialog)
    local data = dialog.data
    local rows = data.rows or 1
    local cols = data.cols or 1
    local total = rows * cols
    dialog:modify{ id="new_cols", text=tostring(total) }
    dialog:modify{ id="range_end", text=tostring(total) }
end

local function updatePreview(dialog)
    local data = dialog.data
    local rows = data.rows or 1
    local cols = data.cols or 1
    local m_top = data.m_top or 0
    local m_bottom = data.m_bottom or 0
    local m_left = data.m_left or 0
    local m_right = data.m_right or 0
    local gap_x = data.gap_x or 0
    local gap_y = data.gap_y or 0
    local color = data.line_color or Color{ r=255, g=0, b=255, a=200 }
    
    if rows <= 0 or cols <= 0 then return end

    local width = spr.width
    local height = spr.height
    
    local available_w = width - m_left - m_right
    local available_h = height - m_top - m_bottom
    
    local sprite_w = math.floor((available_w - (cols - 1) * gap_x) / cols)
    local sprite_h = math.floor((available_h - (rows - 1) * gap_y) / rows)
    
    if sprite_w <= 0 or sprite_h <= 0 then return end

    local previewLayer = nil
    for _, layer in ipairs(spr.layers) do
        if layer.name == "Split Preview" then
            previewLayer = layer
            break
        end
    end
    
    if not previewLayer then
        previewLayer = spr:newLayer()
        previewLayer.name = "Split Preview"
    end
    
    local cel = previewLayer:cel(app.activeFrame)
    if not cel then
        cel = spr:newCel(previewLayer, app.activeFrame)
    end
    
    local img = Image(width, height)
    img:clear()
    
    -- Helper to draw lines since Image:drawLine doesn't exist in Aseprite API
    local function drawHLine(y, x1, x2)
        if y < 0 or y >= height then return end
        for x = math.max(0, x1), math.min(x2, width - 1) do
            img:putPixel(x, y, color)
        end
    end

    local function drawVLine(x, y1, y2)
        if x < 0 or x >= width then return end
        for y = math.max(0, y1), math.min(y2, height - 1) do
            img:putPixel(x, y, color)
        end
    end

    -- Draw outer margins
    drawHLine(m_top, 0, width - 1)
    drawHLine(height - 1 - m_bottom, 0, width - 1)
    drawVLine(m_left, 0, height - 1)
    drawVLine(width - 1 - m_right, 0, height - 1)

    -- Draw grid lines
    for r = 0, rows - 1 do
        local y1 = m_top + r * (sprite_h + gap_y)
        local y2 = y1 + sprite_h
        
        drawHLine(y1, m_left, width - 1 - m_right)
        drawHLine(y2, m_left, width - 1 - m_right)
    end
    
    for c = 0, cols - 1 do
        local x1 = m_left + c * (sprite_w + gap_x)
        local x2 = x1 + sprite_w
        
        drawVLine(x1, m_top, height - 1 - m_bottom)
        drawVLine(x2, m_top, height - 1 - m_bottom)
    end
    
    cel.image = img
    app.refresh()
end

local function executeExport(data)
    local rows = data.rows
    local cols = data.cols
    local m_top = data.m_top or 0
    local m_bottom = data.m_bottom or 0
    local m_left = data.m_left or 0
    local m_right = data.m_right or 0
    local gap_x = data.gap_x
    local gap_y = data.gap_y
    local trim = data.trim
    local prefix = data.prefix
    local outdir = data.outdir
    local merge_new = data.merge_new
    local export_animation = data.export_animation
    local range_from = tonumber(data.range_from) or 1
    local range_to = tonumber(data.range_end) or (rows * cols)
    local target_rows = tonumber(data.new_rows) or 1
    local target_cols = tonumber(data.new_cols) or (rows * cols)
    
    if export_files and (not outdir or outdir == "") then
        return app.alert("Please select an output directory for individual files.")
    end
    
    local width = spr.width
    local height = spr.height
    
    local available_w = width - m_left - m_right
    local available_h = height - m_top - m_bottom
    
    local sprite_w = math.floor((available_w - (cols - 1) * gap_x) / cols)
    local sprite_h = math.floor((available_h - (rows - 1) * gap_y) / rows)
    
    if sprite_w <= 0 or sprite_h <= 0 then
        return app.alert("Invalid dimensions! Check Margins and Spacing.")
    end

    local old_spr = app.activeSprite
    local sprites_list = {}

    app.transaction(function()
        local current_index = 0
        for r = 0, rows - 1 do
            for c = 0, cols - 1 do
                current_index = current_index + 1
                
                -- Skip if out of range
                if current_index >= range_from and current_index <= range_to then
                    local x = m_left + c * (sprite_w + gap_x)
                    local y = m_top + r * (sprite_h + gap_y)
                    
                    -- Create a new sprite for each piece
                    local new_spr = Sprite(sprite_w, sprite_h, spr.colorMode)
                    new_spr:setPalette(spr.palettes[1])
                    
                    -- Copy pixels from original sprite
                    local target_img = new_spr.cels[1].image
                    target_img:drawImage(spr.cels[1].image, -x, -y)
                    
                    -- Handle Trim
                    if trim then
                        app.activeSprite = new_spr
                        app.command.AutocropSprite()
                    end
                    
                    if merge_new or export_animation then
                        table.insert(sprites_list, new_spr)
                    end

                    -- Save the new sprite
                    if export_files then
                        local filename = string.format("%s%d_%d.png", prefix, r + 1, c + 1)
                        local full_path = outdir .. "/" .. filename
                        new_spr:saveAs(full_path)
                    end

                    if not (merge_new or export_animation) then
                        new_spr:close()
                    end
                end
            end
        end

        -- Merge into a new sheet if requested
        if merge_new and #sprites_list > 0 then
            local total = #sprites_list
            
            -- Ensure at least 1 column and row
            local n_cols = math.max(1, target_cols)
            -- Calculate necessary rows to fit all, but use target_rows as a hint if possible
            local n_rows = math.max(1, target_rows)
            if (n_cols * n_rows) < total then
                n_rows = math.ceil(total / n_cols)
            end
            
            -- Find max dimensions (in case of trim)
            local max_w, max_h = 0, 0
            for _, s in ipairs(sprites_list) do
                max_w = math.max(max_w, s.width)
                max_h = math.max(max_h, s.height)
            end
            
            local final_spr = Sprite(n_cols * max_w, n_rows * max_h, spr.colorMode)
            final_spr:setPalette(spr.palettes[1])
            local final_img = final_spr.cels[1].image
            
            for i, s in ipairs(sprites_list) do
                local idx = i - 1
                local row = math.floor(idx / n_cols)
                local col = idx % n_cols
                final_img:drawImage(s.cels[1].image, col * max_w, row * max_h)
                
                -- Only close if NOT also exporting animation
                if not export_animation then
                    s:close()
                end
            end
            
            app.activeSprite = final_spr
        end

        -- Export as animation frames if requested
        if export_animation and #sprites_list > 0 then
            -- Find max dimensions
            local max_w, max_h = 0, 0
            for _, s in ipairs(sprites_list) do
                max_w = math.max(max_w, s.width)
                max_h = math.max(max_h, s.height)
            end
            
            local anim_spr = Sprite(max_w, max_h, spr.colorMode)
            anim_spr:setPalette(spr.palettes[1])
            
            for i, s in ipairs(sprites_list) do
                local frame = nil
                local cel = nil
                if i == 1 then
                    frame = anim_spr.frames[1]
                    cel = anim_spr.cels[1]
                else
                    frame = anim_spr:newFrame()
                    cel = anim_spr:newCel(anim_spr.layers[1], frame)
                end
                
                -- Draw image into the frame
                cel.image:drawImage(s.cels[1].image, 0, 0)
                
                -- Now we can safely close the temp sprite
                s:close()
            end
            
            app.activeSprite = anim_spr
        end
    end)
    
    if not (merge_new or export_animation) then
        app.activeSprite = old_spr
    end
    
    app.alert("Processing complete!")
end

local dialog = Dialog{ title="Sprite Sheet Splitter", onclose=cleanupPreview }

local preset_names = {}
for i, p in ipairs(presets) do preset_names[i] = p.name end

dialog:number{ id="rows", label="Rows/Cols:", text="5", onchange=function() 
    updatePreview(dialog)
    updateTargetN(dialog)
end }
dialog:number{ id="cols", text="9", onchange=function() 
    updatePreview(dialog)
    updateTargetN(dialog)
end }

dialog:separator{ text="Outer Margins (T/L/B/R)" }
dialog:number{ id="m_top", text="0", onchange=function() updatePreview(dialog) end }
dialog:number{ id="m_left", text="0", onchange=function() updatePreview(dialog) end }
dialog:number{ id="m_bottom", text="0", onchange=function() updatePreview(dialog) end }
dialog:number{ id="m_right", text="0", onchange=function() updatePreview(dialog) end }

dialog:separator{ text="Inner Spacing (X/Y)" }
dialog:number{ id="gap_x", text="0", onchange=function() updatePreview(dialog) end }
dialog:number{ id="gap_y", text="0", onchange=function() updatePreview(dialog) end }

dialog:separator{ text="Preview Color" }
dialog:combobox{ id="preset", label="Presets:", options=preset_names, 
    onchange=function()
        local selected = dialog.data.preset
        for _, p in ipairs(presets) do
            if p.name == selected then
                dialog:modify{ id="line_color", color=p.color }
                break
            end
        end
        updatePreview(dialog)
    end 
}
dialog:color{ id="line_color", color=presets[1].color, 
    onchange=function() updatePreview(dialog) end 
}

dialog:separator{ text="Output Settings" }
dialog:check{ id="export_files", label="Export Individual Files", selected=true, 
    onchange=function()
        local v = dialog.data.export_files
        dialog:modify{ id="prefix", visible=v }
        dialog:modify{ id="outdir", visible=v }
    end 
}
dialog:entry{ id="prefix", label="  Prefix:", text="", visible=true }
dialog:file{ id="outdir", label="  OutDir:", save=false, filename=spr.filename:match("(.*[/\\])"), visible=true }

dialog:check{ id="merge_new", label="Merge Sheet", selected=false, 
    onchange=function()
        local v = dialog.data.merge_new
        dialog:modify{ id="new_rows", visible=v }
        dialog:modify{ id="new_cols", visible=v }
    end 
}
dialog:number{ id="new_rows", label="  M/N:", text="1", visible=false }
dialog:number{ id="new_cols", text="45", visible=false }

dialog:check{ id="export_animation", label="Export Anim Frames", selected=false }

dialog:separator{ text="Range (From/End)" }
dialog:number{ id="range_from", text="1" }
dialog:number{ id="range_end", text="45" }

dialog:separator()
dialog:check{ id="trim", label="Trim Transparent Borders", selected=true }

dialog:button{ text="Split and Export", onclick=function() 
    executeExport(dialog.data)
    dialog:close() 
end }
dialog:button{ text="Cancel", onclick=function() 
    dialog:close() 
end }

-- Show initial preview and UI states
updatePreview(dialog)
updateTargetN(dialog) -- Ensure N is correct on start

if dialog.data.export_files ~= nil then
    local v = dialog.data.export_files
    dialog:modify{ id="prefix", visible=v }
    dialog:modify{ id="outdir", visible=v }
end
if dialog.data.merge_new ~= nil then
    local v = dialog.data.merge_new
    dialog:modify{ id="new_rows", visible=v }
    dialog:modify{ id="new_cols", visible=v }
end

dialog:show{ wait=false }
