q3d = require "quinta"

local renderer = nil
local mill = nil
local mill_wheel = nil
local tetrahedron = nil
local tetrahedron_copies = {}

local use_mouse = true

love.window.setMode(640,480,{resizable=true})
love.window.setTitle('Quinta 3D - The world worst 3d engine!!!')


function love.load()
    renderer = q3d.Renderer()
    
    -- You can load a model using only the path
    -- if not texture is given, we use the vertex colors
    -- the engine supports iqm and obj models
    local old_one = q3d.Object3D('assets/cthulhu.iqm')
     
    -- If needed you can add some texture
    local hare = q3d.Object3D('assets/hare.obj',"assets/textures/hare.png")
    
    mill_wheel = q3d.Object3D('assets/mill_wheel.obj',"assets/textures/wood.png")
    
    -- You can have objects that use multiple materials.
    mill = q3d.Object3D(
            "assets/mill3.obj",
                { "assets/textures/window.png",
                  "assets/textures/stone_walls.png",
                  "assets/textures/land.png",
                q3d.Material3D("assets/textures/water.png",nil,"assets/textures/distortion.png")
                }
            )

    --You can create geometry from code, just add vertex list of the faces
    --Order is important to determine the face orientation.
    --Any face not oriented to the camera will not be rendered. 
    --the colors of the vertex will have an effect on the texture used
    --The format is x,y,z,u,v,r,g,b,
    --in this example, we used placeholder uv cords
    --the default color is white.
    local pyramidVerts = {}

    pyramidVerts[ 1] = {-1,1,1, 0,0, 0.1,0.2,1.0}
    pyramidVerts[ 2] = {1,1,-1, 0,1, 0.2,1.0,0.1}
    pyramidVerts[ 3] = {1,-1,1, 1,1}
    
    pyramidVerts[ 4] = {-1,1,1,   0,0,  0.1,0.2,1.0}
    pyramidVerts[ 5] = {-1,-1,-1, 0,1, 1.0,0.2,0.1}
    pyramidVerts[ 6] = {1,1,-1,   1,1, 0.2,1.0,0.1}

    pyramidVerts[ 7] = {1,-1,1,   0,0}
    pyramidVerts[ 8] = {1,1,-1,   0,1, 0.2,1.0,0.1}
    pyramidVerts[ 9] = {-1,-1,-1, 1,1, 1.0,0.2,0.1}
    
    pyramidVerts[10] = {-1,-1,-1, 0,0, 1.0,0.2,0.1}
    pyramidVerts[11] = {-1,1,1,   0,1, 0.1,0.2,1.0}
    pyramidVerts[12] = {1,-1,1,   1,1}
    
    --send the vertex to create a new object, also put a texture
    tetrahedron = q3d.Object3D(pyramidVerts,'assets/textures/distortion_b.png')
    
    --Change position, rotation, and scale of the objects 
    --mill.setPos(0,0,0) --0,0,0 is default position
    hare.setPos(3,1.5,0.2)
    hare.setRot(nil,nil,math.rad(-45))
    
    old_one.setRot(nil,nil,math.rad(-90))
    
    mill_wheel.setPos(0.1,2.7,1.45)
    mill_wheel.setRot(math.rad(90),0,0)
    
    tetrahedron.setScale(0.25,0.25,0.25)
    tetrahedron.setPos(2,2,3)

    -- Important, the objects need to be added to the renderer 
    renderer.addObject(mill)
    renderer.addObject(mill_wheel)
    renderer.addObject(hare)
    renderer.addObject(tetrahedron)
    renderer.addObject(old_one)
    -- Create a set of instances of the tetrahedron.
    -- instances are independent objects that shared the same mesh data and materials
    -- we are gonna set their positions on the update bellow...
    local i = 0
    local scale = 0.35
    while i < 7 do
        local new_t4 = tetrahedron.newInstance()
        new_t4.setScale(scale,scale,scale)

        --add to the render...
        renderer.addObject(new_t4)
        --add to this list, so we can later modify they.
        table.insert(tetrahedron_copies, new_t4)
        
        scale = scale+0.25
        i=i+1
    end

    renderer.bgcolor = {0.0,0.1,0.2}
    renderer.setCameraPos(12,4,4)
    
    -- Set the camera to look on start to the tetrahedron.
    renderer.setCameraLookAt(tetrahedron)
end


function love.draw() 

    renderer.render()
    local info_text = [[
  
  Press SPACE to change between FPS control and set the camera to look at the tetrahedron.
  On FPS control, use the WASD keys to move plus Q and E to go up and down.
  Use ESC to close at any time.
]]
    local cam_pos_x = 'x: '..tostring(math.floor(renderer.camera.pos.x))
    local cam_pos_y = ' y: '..tostring(math.floor(renderer.camera.pos.y))
    local cam_pos_z = ' z: '..tostring(math.floor(renderer.camera.pos.z))
    info_text = info_text..'  '..cam_pos_x..cam_pos_y..cam_pos_z

    love.graphics.setColor(0,0,0)
    love.graphics.print(info_text,-1,0)
    love.graphics.print(info_text,0,1)
    love.graphics.print(info_text,-1,1)
    love.graphics.print(info_text,0,-1)
    love.graphics.setColor(1,1,1)
    love.graphics.print(info_text,0,0)
    
end

local timer = 0
local rotation = 0

function love.update(dt)
    -- simple first-person camera movement
    love.mouse.setRelativeMode(use_mouse)
    if use_mouse then
        
        local mx,my,mz = 0,0,0
        local speed = 0.15
        if love.keyboard.isDown("w") then
            my = my + 1
        end
        if love.keyboard.isDown("a") then
            mx = mx + 1
        end
        if love.keyboard.isDown("s") then
            my = my - 1
        end
        if love.keyboard.isDown("d") then
            mx = mx - 1
        end
        if love.keyboard.isDown("e") then
            mz = mz - dt/speed
        end
        if love.keyboard.isDown("q") then
            mz = mz + dt/speed
        end

        if mx ~= 0 or my ~= 0 then
            local angle = math.atan2(mx,my)
            
            renderer.camera.pos.x = renderer.camera.pos.x + math.sin(renderer.camera.rot.z + angle)*speed*dt*60
            renderer.camera.pos.y = renderer.camera.pos.y - math.cos(renderer.camera.rot.z + angle)*speed*dt*60
            
        end
        renderer.camera.pos.z = renderer.camera.pos.z + mz
    else
       renderer.setCameraLookAt(tetrahedron)
    end

    -- Make the tetrahedron and the copies spin.
    timer = timer + dt/8
    
    local angle = timer*3+math.pi*0.5
    local npos = {math.cos(angle)*5,math.sin(angle)*5,3}
    tetrahedron.setPos(unpack(npos))
    tetrahedron.setRot(unpack(npos))

    local i = 1
    while tetrahedron_copies[i] do
        local angle1 = math.rad((i/7)*360)-angle
        local x = math.sin(-angle1)*(8)
        local y = math.cos(-angle1)*(8)
        tetrahedron_copies[i].setPos(x,y,math.cos(angle1*3))
        tetrahedron_copies[i].setRot(angle1,-angle1*2,angle1*3)
        i=i+1
    end

    -- Here is defined the animation of the mill wheel.
    rotation = rotation + dt*10
    if rotation > 360 then rotation = 0 end
    mill_wheel.setRot(nil,nil,math.rad(-rotation))

    -- The animation of the texture of the mill water texture
    local mesh_list = mill.getMeshByMaterial('water')
    for _,mesh in pairs(mesh_list) do
        local current_vertex =  mesh.first
        local last_vertex = mesh.last
        while current_vertex < last_vertex do
            -- 1 is position cords, 2 is uv cords, anything after that is format dependent.
            -- for details of the format, see model_name.model.mesh:getVertexFormat( )
            -- and the love Mesh:getVertexFormat( ) API
            local u,v = mill.getVertexAttributes(current_vertex,2)
            u = u-dt*0.05 --original_uv[first][1]+0.25*(frame_list[frame]-1)
            v = v-dt*0.05
            mill.setVertexAttribute(current_vertex,2,{u,v})
            current_vertex = current_vertex+1
        end
    end
    
    -- The animation on the texture of the tetrahedron.
    -- Alter the mesh, also changes all their instances...
    mesh_list = tetrahedron.getMeshByMaterial('Material_0')
    for _,mesh in pairs(mesh_list) do
        local current_vertex =  mesh.first
        local last_vertex = mesh.last
        while current_vertex < last_vertex do
            local u,v = tetrahedron.getVertexAttributes(current_vertex,2)
            u = u-dt --original_uv[first][1]+0.25*(frame_list[frame]-1)
            v = v+dt
            tetrahedron.setVertexAttribute(current_vertex,2,{u,v})
            current_vertex = current_vertex+1
        end
    end
    
end

function love.mousemoved(x,y, dx,dy)
    if use_mouse then
       local z_rot = renderer.camera.rot.z - math.rad(dx * 0.5)
       local x_rot = math.max(math.min(renderer.camera.rot.x - math.rad(dy * 0.5), math.rad(170)), math.rad(20))
       renderer.setCameraRot(x_rot,nil,z_rot)
    end
end

function love.keypressed(a, id)
    if id == 'escape' then
        love.event.quit()
    end
    if id == 'space' then
        use_mouse = not use_mouse
    end
end
