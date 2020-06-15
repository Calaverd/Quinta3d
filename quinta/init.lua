local base = (...):gsub('%.?init$', '')

cpml = require(base.."/cpml")
iqm = require(base.."/iqm")
obj_reader = require(base.."/obj_reader")
ffi = require "ffi"
--anim9 = require "quinta/anim9"

local quinta = {
	_LICENSE     = "Quinta 3D is distributed under the terms of the MIT license. See LICENSE.md.",
	_URL         = "https://github.com/excessive/iqm",
	_VERSION     = "0.0.1",
	_DESCRIPTION = "A simple 3d engine for LÖVE.",
}

local DEFAULT_SHADER = nil 
local DEFAULT_DISTORTION = nil
local DEFAULT_TEXTURE = nil 
--local UPDIR = cpml.vec3(0,0,1)

local function startupRender()
    print(base)
    DEFAULT_SHADER = love.graphics.newShader(base..'/render_shader.glsl')
    
    local temp_canvas = love.graphics.newCanvas(16,16)
    love.graphics.setCanvas(temp_canvas)
    love.graphics.clear(0.5,0.5,0.5,1)
    love.graphics.setCanvas()
    DEFAULT_DISTORTION = love.graphics.newImage(temp_canvas:newImageData())
    temp_canvas = nil

    temp_canvas = love.graphics.newCanvas(16,16)
    love.graphics.setCanvas(temp_canvas)
    love.graphics.clear(1,1,1,1)
    love.graphics.setCanvas()
    DEFAULT_TEXTURE = love.graphics.newImage(temp_canvas:newImageData())
    temp_canvas = nil
end

local function TransposeMatrix(mat)
	local m = cpml.mat4.new()
	return cpml.mat4.transpose(m, mat)
end

local function InvertMatrix(mat)
	local m = cpml.mat4.new()
	return cpml.mat4.invert(m, mat)
end


-- Cheap Heap implementation.
-- Is build to be data agnostic, so it can work comparing
-- arbitrary data types.
-- Is used for the priority queue
local function CHeap()
    local self = {}
    
    local last = 0 --the id of the last inserted item
    local container = {}
    
    function self.compare(a,b)
        return a <= b
    end
    
    function self.clear()
        container = {}
        last = 0
    end
    
    local function getParentOf(id)
        if math.fmod(id,2) == 0 then return id/2 end
        return (id-1)/2 
    end
    
    function self.push(data)
        --is first element.
        if last <= 1 then
            container[1] = data
            last = 2
            return nil
        end
        
        local heap_property = false
        local current = last
        local parent = 0
        container[current] = data
        
        while not heap_property do
            parent = getParentOf(current)
            if self.compare( container[current], container[parent] ) then
                --swap current and parent
                container[current] = container[parent]
                container[parent] = data
                current = parent
            else
                heap_property = true
            end
            if current <= 1 then
                heap_property = true
            end        
        end
        last = last+1
        
    end
    
    function self.pop()
        --sawp first and last value
        local top = container[1]
        container[1] = container[last-1]
        container[last-1] = nil
        
        local current = 1
        local heap_property = false
        --print('*** START ***')
        while not heap_property do
            local left = 2*current
            local right = 2*current + 1
            local choosed = current
            -- Exist the right node?
            if container[right] then
                if self.compare(container[left], container[right]) then
                    choosed = left
                else
                    choosed = right
                end
                
                if self.compare(container[choosed],container[current]) then
                    --swap the value
                    local temp = container[choosed]
                    container[choosed] = container[current]
                    container[current] = temp
                    current = choosed   
                else
                    heap_property = true
                end
            -- Exist the left node?
            elseif container[left] then
                if self.compare(container[left],container[current]) then
                    --swap the value
                    choosed = left
                    local temp = container[choosed]
                    container[choosed] = container[current]
                    container[current] = temp
                    current = choosed   
                else
                    heap_property = true
                end
            else
                heap_property = true
            end
        end

        last = math.max(last-1,0)
        
        return top
    end
    
    function self.peek()
        return container[1]
    end
    
    function self.getSize()
        return last
    end
    
    return self
end


function quinta.newModel(vertex_data,material_data)
    local model = {}
    local format = {
        {"VertexPosition", "float", 3},
        {"VertexTexCoord", "float", 2},
        {"VertexColor", "float", 3},
        {"VertexNormal", "float", 3}
    }

    model.mesh = nil
    model.meshes = {}
    if not material_data then --create a empty material data
        local temp = {}
        temp.first    = 1 --the first vertex that uses that material....
        temp.count    = math.floor(#vertex_data) --the number of vertex that use that material
        temp.last     = temp.first + temp.count
        temp.material = "Material_0"
        temp.name     = "UserMesh "..tostring(model)
        table.insert(model.meshes,temp)
    else
        local i = 1
        while material_data[i] do 
            local temp = {}
            temp.first    = material_data[i+1] --the first vertex that uses that material....
            temp.count    = material_data[i+2] --the number of vertex that use that material
            temp.last     = material_data[i+3]
            temp.material = material_data[i]
            temp.name     = material_data[i]..'.mesh'
            table.insert(model.meshes,temp)
            i=i+4
        end
    end
    print('num faces = ', #vertex_data)
    if #vertex_data > 0 then
        for i=1, #vertex_data do
            --uv coords ? 
            if #vertex_data[i] < 5 then
                vertex_data[i][4] = love.math.random(0,1)
                vertex_data[i][5] = love.math.random(0,1)
            end

            --vertex color ? 
            if #vertex_data[i] < 6 then
                vertex_data[i][6] = 1
                vertex_data[i][7] = 1
                vertex_data[i][8] = 1 
            end

            -- normals? 
            if #vertex_data[i] < 9 then
                local normal_vector = cpml.vec3.normalize(
                    cpml.vec3(
                        vertex_data[i][1],
                        vertex_data[i][2],
                        vertex_data[i][3])
                    )
                vertex_data[i][9] = normal_vector.x
                vertex_data[i][10] = normal_vector.y
                vertex_data[i][11] = normal_vector.z
            end 
        end

        model.mesh = love.graphics.newMesh(format, vertex_data, "triangles")
    end

    return model
end

local function loadObj(path)
    local obj = obj_reader.load(path)
	local faces = {}
	local verts = {}
	
	for _,v in ipairs(obj.v) do
		table.insert(verts, {v.x,v.y,v.z})
	end
  
  for _, vrtx in ipairs(obj.f) do
      --add the first 3 vertices 
      local j = 1
      while j < 4 do
          local x, y, z = verts[vrtx[j].v][1], verts[vrtx[j].v][2], verts[vrtx[j].v][3]
          local u, v =  obj.vt[vrtx[j].vt].u,  obj.vt[vrtx[j].vt].v
          local nx, ny, nz = obj.vn[vrtx[j].vn].x, obj.vn[vrtx[j].vn].y, obj.vn[vrtx[j].vn].z
          -- {position, uv, rgb, normal}
          table.insert(faces, {x,y,z, u,v, 1,1,1, nx,ny,nz})
          j=j+1
      end
  end
	return faces, obj.mtl
end

local function validateTextureData(texture_data)
    if type(texture_data) == "string" then
        local texture = love.graphics.newImage(texture_data, { mipmaps = true })
        texture:setFilter("nearest", "nearest") 
        texture:setWrap("repeat","repeat")
        return texture
    end
    return texture_data
end

function quinta.Material3D(diffuse,normal,distortion, layer)
    local self = {}
    self.diffuse      = validateTextureData(diffuse) or DEFAULT_TEXTURE
    self.distortion   = validateTextureData(distortion) or DEFAULT_DISTORTION
    self.normal       = validateTextureData(normal) 
    self.render_layer = layer or 1
    self.wired = false
    --print('new material diffuse is:', self.diffuse)
    return self
end


function quinta.Camera(camera_type, renderWidth, renderHeight)
    local self = {}
    local fov = 60
    local nearClip = 0.0001
    local farClip = 1000
    local width, height = love.window.getMode( )
    self.renderHeight = renderHeight or height
    self.renderWidth = renderWidth or width
    self.pos = cpml.vec3(0,0,3)
    self.rot = cpml.vec3(0,0,0)
    self.scale = cpml.vec3(1,1,1)
    self.camera_view = cpml.mat4()
    self.camera_inverse = InvertMatrix(self.camera_view)
            
    if not camera_type or camera_type == 'perspective' then
        self.type = 'perspective'
        self.matrix = TransposeMatrix(
            cpml.mat4.from_perspective(fov, (self.renderWidth/self.renderHeight), nearClip, farClip)
            )
    else
        self.type = 'ortho'
        local ratio =  (self.renderWidth/self.renderHeight)
        self.matrix = TransposeMatrix(cpml.mat4.from_ortho(-10,10,5*ratio,-5*ratio,0.0001,10))
    end

    function self.setPos(x,y,z)
        if x then self.pos.x = x end
        if y then self.pos.y = y end
        if z then self.pos.z = z end
    end

    function  self.setRot(x,y,z)
        if x then self.rot.x = x end
        if y then self.rot.y = y end
        if z then self.rot.z = z end
    end

    function  self.lookAt(target)
        local v2d_1 = cpml.vec2(self.pos.x,self.pos.y)
        local v2d_trg = cpml.vec2(target.pos.x,target.pos.y)
        local angle = cpml.vec2.angle_to(v2d_1,v2d_trg )
        local angle2 = math.atan2( cpml.vec2.dist(v2d_1,v2d_trg), self.pos.z-target.pos.z )
        
        self.rot.z = angle-math.rad(90)
        self.rot.x = angle2
    end

    function self.calculateViewMatrix()
        self.camera_view = cpml.mat4()
        self.camera_view:translate(self.camera_view, cpml.vec3(self.pos.x,-self.pos.y,-self.pos.z))
    
        self.camera_view:rotate(self.camera_view, self.rot.z, cpml.vec3.unit_z)
        self.camera_view:rotate(self.camera_view, self.rot.y, cpml.vec3.unit_y)
        self.camera_view:rotate(self.camera_view, self.rot.x, cpml.vec3.unit_x)
        self.camera_view = TransposeMatrix(self.camera_view)
    end            
    


    return self
end


function quinta.Instance3D()
    local self = {}
    self.model = nil
    self.culling = 'back'
    self.pos = cpml.vec3(0,0,0)
    self.rot = cpml.vec3(0,0,0)
    self.scale = cpml.vec3(1,1,1)
    self.materials = nil 
    self.model_transform = nil
    self.model_rot_transform = nil
    self.wireframe = false
    self.animation = nil

    function  self.setWireframe(val)
        self.wireframe = val or false
    end

    --we defined this function is to tranform the mesh to be draw
    function self.transform()
        --move the model...
        local new_transform = nil
        new_transform = cpml.mat4.identity()
        
        -- apply rotations
        new_transform:scale(new_transform, self.scale)

        new_transform:rotate(new_transform, self.rot.z , cpml.vec3.unit_z)
        new_transform:rotate(new_transform, self.rot.y , cpml.vec3.unit_y)
        new_transform:rotate(new_transform, self.rot.x , cpml.vec3.unit_x)
        
        new_transform:translate(new_transform, cpml.vec3(-self.pos.x,self.pos.y,self.pos.z))

        self.model_transform = TransposeMatrix(new_transform)

        new_transform = cpml.mat4.identity()
        new_transform:translate(new_transform, cpml.vec3(0,0,0))
        -- apply rotations
        new_transform:rotate(new_transform, -self.rot.x , cpml.vec3.unit_x)
        new_transform:rotate(new_transform, -self.rot.y , cpml.vec3.unit_y)
        new_transform:rotate(new_transform, -self.rot.z , cpml.vec3.unit_z)

        self.model_rot_transform = new_transform
        --]]
    end

    self.transform()
    
    function self.setPos(x,y,z)
        if x then self.pos.x = x end
        if y then self.pos.y = y end
        if z then self.pos.z = z end
        self.transform()
    end

    function  self.setRot(x,y,z)
        if x then self.rot.x = x end
        if y then self.rot.y = y end
        if z then self.rot.z = z end
        self.transform()
    end
    
    function  self.setScale(x,y,z)
        if x then self.scale.x = x end
        if y then self.scale.y = y end
        if z then self.scale.z = z end
        self.transform()
    end

    function self.renderMe(shader, renderWidth,renderHeight, layer)
        for _, mesh in ipairs(self.layer_meshes[layer]) do
            --this is horrible... 
            shader:send("Model_Matrix", self.model_transform)
            --shader:send("Model_Rot_Matrix", self.model_rot_transform)
            --shader:send("use_vertex_color", (self.materials[mesh.material] == nil))
            --shader:send("use_animation",false)
            self.model.mesh:setTexture(self.materials[mesh.material].diffuse)
            shader:send("distortion_map",self.materials[mesh.material].distortion)
            local tw, th = self.materials[mesh.material].diffuse:getDimensions( )
            shader:send("texture_size",{tw,th})
            love.graphics.setMeshCullMode(self.culling) --back
            love.graphics.setWireframe(self.materials[mesh.material].wired) --self.wireframe
            --render only the vertex of the material...
            self.model.mesh:setDrawRange(mesh.first, mesh.last)
            love.graphics.setColor(1,1,1,1)
            love.graphics.draw(self.model.mesh, -renderWidth/2, -renderHeight/2)
            
            love.graphics.setMeshCullMode("none")
        
        end
        love.graphics.setWireframe(false)
    end

    function self.getVertexAttributes(vertex_num, attributeindex)
        if not attributeindex then
            return self.model.mesh:getVertex(vertex_num)
        end
        return self.model.mesh:getVertexAttribute(vertex_num,attributeindex)
    end

    function self.setVertexAttribute(vertex_num, attributeindex,values)
        self.model.mesh:setVertexAttribute(vertex_num,attributeindex,unpack(values))
    end

    function self.getMeshByMaterial(material_name)
        local mesh_list = {}
        if not self.materials[material_name] then --material not even exist!!!
            return mesh_list
        end
        for _,mesh in pairs(self.model.meshes) do
            if mesh.material == material_name then       
                table.insert(mesh_list, mesh)
            end
        end
        return mesh_list
    end

    function self.composedBillboardTo(target)
        local v2d_1 = cpml.vec2(self.pos.x,self.pos.y)
        local v2d_trg = cpml.vec2(target.pos.x,target.pos.y)
        local angle2 = math.atan2( cpml.vec2.dist(v2d_1,v2d_trg), target.pos.z-self.pos.z )
        local new_transform = cpml.mat4.identity()

        self.rot.z = math.rad(180)-target.rot.z
        self.rot.x = angle2-math.rad(90)
        
        --I hate the Gimbal lock problem...
        new_transform:rotate(new_transform, self.rot.y , cpml.vec3.unit_y)
        new_transform:rotate(new_transform, self.rot.x , cpml.vec3.unit_x)
        new_transform:rotate(new_transform, self.rot.z , cpml.vec3.unit_z)

        new_transform:translate(new_transform, cpml.vec3(-self.pos.x,self.pos.y,self.pos.z))
        self.model_transform = TransposeMatrix(new_transform)
    end

    function self.billboardTo(target)
        self.rot.z = math.rad(180)-target.rot.z
        self.transform()
    end

    function self.faceTo(target)
        local angle = cpml.vec2.angle_to(cpml.vec2(self.pos.x,-self.pos.y),cpml.vec2(target.pos.x,-target.pos.y))
        self.setRot(nil,nil,math.rad(90)+angle)
    end

    function  self.lookAt(target)
        local v2d_1 = cpml.vec2(self.pos.x,self.pos.y)
        local v2d_trg = cpml.vec2(target.pos.x,target.pos.y)
        local angle = cpml.vec2.angle_to(v2d_1,v2d_trg )
        local angle2 = math.atan2( cpml.vec2.dist(v2d_1,v2d_trg), self.pos.z-target.pos.z )
        local new_transform = cpml.mat4.identity()
        
        self.rot.z = angle-math.rad(90)
        self.rot.x = angle2-math.rad(90)
        
        --I hate the Gimbal lock problem...
        new_transform:rotate(new_transform, self.rot.y , cpml.vec3.unit_y)
        new_transform:rotate(new_transform, -self.rot.x , cpml.vec3.unit_x)
        new_transform:rotate(new_transform, -self.rot.z , cpml.vec3.unit_z)

        new_transform:translate(new_transform, cpml.vec3(-self.pos.x,self.pos.y,self.pos.z))
        self.model_transform = TransposeMatrix(new_transform)
    end

    return self
end

function quinta.Object3D(data,texture_data)
    local self = quinta.Instance3D()
    if type(data) == 'string' then
        --check the file extension 
        if string.sub(data, -3) == 'obj' then
            --is a obj file..
            self.model = quinta.newModel(loadObj(data))
            --self.culling = 'front'
        else
            self.model = iqm.load(data,false,true)
            --self.animation = anim9(iqm.load_anims(data))
        end
    else
        --we asumed is not a url, but user mesh data
        self.model = quinta.newModel(data)
    end
    print(data)

    self.materials = {}
    self.layer_meshes = {}
    self.layer_meshes[1] = {}
    self.layer_meshes[2] = {}
    self.layer_meshes[3] = {}
    
    local texture = nil
    --local material = nil 
    if type(texture_data) == "string" then
        texture = love.graphics.newImage(texture_data, { mipmaps = true })
        texture:setFilter("nearest", "nearest") 
        texture:setWrap("repeat","repeat")
    end

    if type(texture_data) == "table" then
        if texture_data.diffuse then --is a single material... 
            for _,mesh in pairs(self.model.meshes) do
                if not self.materials[mesh.material] then
                    self.materials[mesh.material] = texture_data
                end
                local layer = self.materials[mesh.material].render_layer
                table.insert(self.layer_meshes[layer], mesh)
            end
        else --is a list of materials
            
            local i = 1
            local n_texture = nil
            for _,mesh in pairs(self.model.meshes) do
                if not self.materials[mesh.material] then
                    if type(texture_data[i]) == "string" then --load a new texture
                        if i <= #texture_data then
                            n_texture = love.graphics.newImage(texture_data[i], { mipmaps = true })
                            n_texture:setFilter("nearest", "nearest")
                            n_texture:setWrap("repeat","repeat")
                        end
                        print('>>',mesh.material,texture_data[i])
                        
                        self.materials[mesh.material] = quinta.Material3D(n_texture)
                    elseif type(texture_data[i]) == "table" then --asume is a material
                        self.materials[mesh.material] = texture_data[i]
                    else --asume is a Love 2d Image
                        self.materials[mesh.material] = quinta.Material3D(texture_data[i])
                    end
                end
                --add this mesh to the layer that is on the material
                local layer = self.materials[mesh.material].render_layer
                print(">>> added to layer "..tostring(layer))
                table.insert(self.layer_meshes[layer], mesh)
                
                if i <= #texture_data then
                    i=i+1  
                end
            end
        end
    else
        -- [[
        --print('else')
        for _,mesh in pairs(self.model.meshes) do
            --print(mesh.material,texture_data, k)
            if not self.materials[mesh.material] then 
                self.materials[mesh.material] = quinta.Material3D(texture)
            end
            local layer = self.materials[mesh.material].render_layer
            table.insert(self.layer_meshes[layer], mesh)
        end
        --]]
    end

    function  self.newInstance()
        local new_instance = quinta.Instance3D()
        new_instance.model = self.model
        new_instance.materials = self.materials
        new_instance.layer_meshes = self.layer_meshes
        new_instance.culling = self.culling
        return new_instance
    end

    return self
end

--The only job of this class is render the objects, nothing more
--use it to render a single object, or add objects to be render on a single pass
--needs a camera to render
function quinta.Renderer(resolution_x,resolution_y)
    local self = {}
    --local camTransform = cpml.mat4()
    --local obj_pos2d = cpml.vec2.new(0,0)
    local cam_dir2d = cpml.vec2.new(0,0)
    
    local love_width, love_height = love.graphics.getDimensions( )
    local renderWidth  = resolution_x or love_width 
    local renderHeight = resolution_y or love_height  

    self.camera = quinta.Camera('perspective',renderWidth,renderHeight)
    self.shader = nil
    self.canvas = love.graphics.newCanvas( self.camera.renderWidth, self.camera.renderHeight)
    startupRender()
    self.shader = DEFAULT_SHADER
    local object_list = {}
    --local light_list = {}

    --local ambientLight = 0.25

    self.light = {}
    self.light.pos = {0,0,0}
    self.light.color = {1,1,1}
    self.bgcolor = {0,0,0}
    self.offset_d = 0
    self.render_percent = 0

    self.heap = CHeap()
    self.heap.compare = function(a,b)
        local distance_a = cpml.vec3.dist2(self.camera.pos, a.pos)
        local distance_b = cpml.vec3.dist2(self.camera.pos, b.pos)
        return distance_a >= distance_b
    end
    
    function self.startUp()
        
    end

    --function self.addLight(light)
    --    table.insert(object_list,object)
    --end

    function self.addObject(object)
        table.insert(object_list,object)
        --print(#object_list)
    end

    function self.removeObject(model)
        local i = 1
        while object_list[i] do
            if object_list[i] == model then
                table.remove(object_list, i)
                break
            end
        end
    end

    function  self.setCamera(new_camera)
        self.camera = new_camera
    end

    function self.setCameraPos(x,y,z)
        self.camera.setPos(x,y,z)
    end

    function self.setCameraRot(x,y,z)
        self.camera.setRot(x,y,z)
    end

    function self.rotateCamera(dx,dy,dz)
        self.camera.rot.x = self.camera.rot.x + (dx or 0)
        self.camera.rot.y = self.camera.rot.y + (dy or 0)
        self.camera.rot.z = self.camera.rot.z + (dz or 0) 
    end

    function self.setCameraLookAt(target)
        self.camera.lookAt(target)
    end

    function self.setShader()
        -- body
    end

    --function self.renderAll(shader)
    --    
    --end

    function self.render()
        
        love.graphics.setCanvas({self.canvas, depth=true})
        
            love.graphics.clear(self.bgcolor[1],self.bgcolor[2],self.bgcolor[3],1)

            love.graphics.setColor(1,1,1)

            love.graphics.setDepthMode("lequal", true)
            love.graphics.setShader(self.shader)

            self.camera.calculateViewMatrix()
            local MVP = self.camera.camera_view * self.camera.matrix
            self.camera.camera_inverse = InvertMatrix(MVP)

            self.shader:send("offset_d", self.offset_d)
            self.shader:send("MVP", MVP)
            --self.shader:send("camPos", {self.camera.pos.x,self.camera.pos.y,self.camera.pos.z})
            --self.shader:send("lightPos",self.light.pos,{0,0,0})
            
            self.heap.clear()


            cam_dir2d.x = math.sin(self.camera.rot.z)
            cam_dir2d.y = -math.cos(self.camera.rot.z)
            local i = 1
            while object_list[i] do
                --the objet is marked as "above all", then render it here and now

                --else, treat it as every other object
                --check it it is on front of the camera, 
                -- in this case, from a ray 2 units behind the plane of the camera
                --if it is inside, then add to the short
                --obj_pos2d.x = object_list[i].pos.x-self.camera.pos.x+cam_dir2d.x*2
                --obj_pos2d.y = object_list[i].pos.y-self.camera.pos.y+cam_dir2d.y*2
                --if math.deg(cam_dir2d:angle_between(obj_pos2d)) < 60 then

                    self.heap.push(object_list[i])
                --end
                i=i+1
            end
            
            local num_obj_to_render = self.heap.getSize()
            if num_obj_to_render > 0 then
                self.render_percent = (num_obj_to_render/i)*100
            else
                self.render_percent = 0
            end
            
            local object_to_render = self.heap.pop()
            while object_to_render do
                --layer one for solid 
                object_to_render.renderMe(self.shader, self.camera.renderWidth, self.camera.renderHeight, 1)
                --layer two for translucid
                object_to_render.renderMe(self.shader, self.camera.renderWidth, self.camera.renderHeight, 2)
                object_to_render = self.heap.pop() 
            end

            love.graphics.setShader()

        love.graphics.setCanvas()

        love.graphics.setColor(1,1,1)
        
        --this is the cheap way to have a resisable window, just scale the canvas to the window size
        --this not respect aspec ratio...
        love_width, love_height = love.graphics.getDimensions( )
        local factor_x = love_width/self.camera.renderWidth
        local factor_y = love_height/self.camera.renderHeight
        local canvas_size_x = (self.camera.renderWidth*factor_x)/2
        local canvas_size_y = (self.camera.renderHeight*factor_y)/2
        love_width = love_width/2
        love_height = love_height/2
        love.graphics.draw(self.canvas,
                love_width-canvas_size_x, love_height-canvas_size_y, 0, factor_x, factor_y)
        
        self.offset_d = self.offset_d +love.timer.getDelta( )
        if self.offset_d > 5 then self.offset_d = 0 end 
    end
    
    return self
end

return quinta
