local base = (...):gsub('%.?init$', '')

cpml = require(base.."/cpml")
iqm = require(base.."/iqm")
obj_reader = require(base.."/obj_reader")
ffi = require "ffi"
--anim9 = require "quinta/anim9"

local quinta = {
	_LICENSE     = "Quinta 3D is distributed under the terms of the MIT license. See LICENSE.",
	_URL         = "https://github.com/excessive/iqm",
	_VERSION     = "0.0.1",
	_DESCRIPTION = "A simple 3d engine for LÖVE.",
}

--We borrow intersection math from cpml
quinta.intersect = cpml.intersect
quinta.cpml = cpml

local DEFAULT_SHADER = nil 
local DEFAULT_DISTORTION = nil
local DEFAULT_TEXTURE = nil
--we create a default cube mesh to show aabb 
local DEFAULT_CUBE_MODEL = nil
local DEFAULT_PLANE_MODEL = nil
--any small bost of speed is welcome... 
--CPMLF = Cirno Perfect Math Library Function
local CPMLF_IDENTITY_MATRIX = cpml.mat4.identity
local CPMLF_VEC3_DIST2 = cpml.vec3.dist2
local CPMLF_TRANSPOSE_MATRIX = cpml.mat4.transpose
local CPMLF_NEW_MATRIX = cpml.mat4.new
local CPMLF_INVERT_MATRIX = cpml.mat4.invert
local CPMLF_VEC2_ANGLE2 = cpml.vec2.angle_to
local CPMLF_VEC2_DIST = cpml.vec2.dist
local CPMLF_NEW_VEC2 = cpml.vec2
local CPMLF_NEW_VEC3 = cpml.vec3
--
local CPMLC_UNIT_V3_X = cpml.vec3.unit_x
local CPMLC_UNIT_V3_Y = cpml.vec3.unit_y
local CPMLC_UNIT_V3_Z = cpml.vec3.unit_z

local MAX = math.max
local MIN = math.min
--local UPDIR = CPMLF_NEW_VEC3(0,0,1)

local function table_append(i_table, ...)
    --create a copy of the table...
    local o_table = {}
    for k,v in pairs(i_table) do
        o_table[k] = v
    end
    
    for _,v in pairs({...}) do
        o_table[#o_table+1] = v
    end
    
    return o_table
end



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
    
    DEFAULT_CUBE_MODEL =  quinta.newModel(quinta.pCubeDF(1,1,1))
    DEFAULT_PLANE_MODEL =  quinta.newModel(quinta.pPlaneDF(1,1))
end

local function TransposeMatrix(mat)
	local m = CPMLF_NEW_MATRIX()
	return CPMLF_TRANSPOSE_MATRIX(m, mat)
end

local function InvertMatrix(mat)
	local m = CPMLF_NEW_MATRIX()
	return CPMLF_INVERT_MATRIX(m, mat)
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

function quinta.ObjToColTriangles(path)
    local obj = obj_reader.load(path)
	local triangles = {}
    local verts = {}
	
	for _,v in ipairs(obj.v) do
		table.insert(verts, {v.x,v.y,v.z})
	end
  
    local vertex = {}
    for _, vrtx in ipairs(obj.f) do
        --add the first 3 vertices 
        local j = 1
        while j < 4 do
            vertex[j] = CPMLF_NEW_VEC3(verts[vrtx[j].v][1]*(-1), verts[vrtx[j].v][2], verts[vrtx[j].v][3])
            j=j+1
        end
        --.colTriangleMStatic
        table.insert(triangles, quinta.colTriangle(vertex[1],vertex[2],vertex[3]) )
    end
    
	return triangles
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

function quinta.newMesh(vertex_data)
    local mesh_format = {
        {"VertexPosition", "float", 3},
        {"VertexTexCoord", "float", 2},
        {"VertexColor", "float", 3},
        {"VertexNormal", "float", 3}
    }
    
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
                local normal_vector = CPMLF_NEW_VEC3.normalize(
                    CPMLF_NEW_VEC3(
                        vertex_data[i][1],
                        vertex_data[i][2],
                        vertex_data[i][3])
                    )
                vertex_data[i][9] = normal_vector.x
                vertex_data[i][10] = normal_vector.y
                vertex_data[i][11] = normal_vector.z
            end 
        end
        return love.graphics.newMesh(mesh_format, vertex_data, "triangles")
    end
    return nil
end


function quinta.newModel(vertex_data,material_data)
    local model = {}
    

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
    --print('num faces = ', #vertex_data)
    model.mesh = quinta.newMesh(vertex_data)

    return model
end

--the basic description of location, rotation and scale of a object in 3d Space
function quinta.Space3D()
    local self = {}
    
    self.pos = CPMLF_NEW_VEC3(0,0,0)
    self.rot = CPMLF_NEW_VEC3(0,0,0)
    self.scale = CPMLF_NEW_VEC3(1,1,1)
    
    function self.getPosAsVector()
        return self.pos
    end
    
    function self.getPos()
        return self.pos.x, self.pos.y, self.pos.z
    end
    
    function self.getRotAsVector()
        return self.rot
    end
    
    function self.getRot()
        return self.rot.x, self.rot.y, self.rot.z
    end
    
    function self.getScaleAsVector()
        return self.scale
    end
    
    function self.getScale()
        return self.scale.x, self.scale.y, self.scale.z
    end
    
    function self.setPos(x,y,z)
        if x then self.pos.x = x end
        if y then self.pos.y = y end
        if z then self.pos.z = z end
        self.calculateTransform()
    end

    function  self.setRot(x,y,z)
        if x then self.rot.x = x end
        if y then self.rot.y = y end
        if z then self.rot.z = z end
        self.calculateTransform()
    end
    
    function  self.setScale(x,y,z)
        if x then self.scale.x = x end
        if y then self.scale.y = y end
        if z then self.scale.z = z end
        self.calculateTransform()
    end
    
    return self
end

function quinta.pTriangleFromVectors(vA,vB,vC)
    --a cube is composed of 12 triangles
    --and 8 vertex, and later append their uv coords
    local face_list = {}
    
    local A = {vA.x, vA.y, vA.z}
    local B = {vB.x, vB.y, vB.z}
    local C = {vC.x, vC.y, vC.z}
    
    face_list[#face_list+1] = table_append(A,0,0)
    face_list[#face_list+1] = table_append(B,1,0)
    face_list[#face_list+1] = table_append(C,1,1)
    return face_list
end

function quinta.pPlaneFromVectors(vA,vB,vC,vD)
    local face_list = {}
    
    local A = {vA.x, vA.y, vA.z}
    local B = {vB.x, vB.y, vB.z}
    local C = {vC.x, vC.y, vC.z}
    local D = {vD.x, vD.y, vD.z}
    
    face_list[#face_list+1] = table_append(A,0,0)
    face_list[#face_list+1] = table_append(B,1,0)
    face_list[#face_list+1] = table_append(C,1,1)
    face_list[#face_list+1] = table_append(C,1,1)
    face_list[#face_list+1] = table_append(D,0,1)
    face_list[#face_list+1] = table_append(A,0,0)
    
    return face_list
end

function quinta.pPlane(sw,sh)
    --a cube is composed of 12 triangles
    --and 8 vertex, and later append their uv coords
    local face_list = {}
    local x0,y0,z0 = -sw/2, -sh/2, 0
    local x1,y1,z1 = sw/2, sh/2, 0
    local B = {x0, y0, z1}
    local C = {x1, y0, z1}
    local F = {x0, y1, z1}
    local G = {x1, y1, z1}
    
    face_list[#face_list+1] = table_append(C,0,0)
    face_list[#face_list+1] = table_append(B,1,0)
    face_list[#face_list+1] = table_append(F,1,1)
    face_list[#face_list+1] = table_append(F,1,1)
    face_list[#face_list+1] = table_append(G,0,1)
    face_list[#face_list+1] = table_append(C,0,0)
    
    return face_list
end

--build a cube from their min and max vectors
function quinta.pCubeMinMax(x0,y0,z0,x1,y1,z1)
    --a cube is composed of 12 triangles
    --and 8 vertex, and later append their uv coords
    local face_list = {}
    
    local A = {x0, y0, z0}
    local B = {x0, y0, z1}
    local C = {x1, y0, z1}
    local D = {x1, y0, z0}
    local E = {x0, y1, z0}
    local F = {x0, y1, z1}
    local G = {x1, y1, z1}
    local H = {x1, y1, z0}
    
    face_list[#face_list+1] = table_append(A,1,1)
    face_list[#face_list+1] = table_append(B,1,0)
    face_list[#face_list+1] = table_append(C,0,0)
    face_list[#face_list+1] = table_append(C,0,0)
    face_list[#face_list+1] = table_append(D,0,1)
    face_list[#face_list+1] = table_append(A,1,1)
    
    face_list[#face_list+1] = table_append(A,0,1)
    face_list[#face_list+1] = table_append(E,1,1)
    face_list[#face_list+1] = table_append(F,1,0)
    face_list[#face_list+1] = table_append(F,1,0)
    face_list[#face_list+1] = table_append(B,0,0)
    face_list[#face_list+1] = table_append(A,0,1)
    
    face_list[#face_list+1] = table_append(D,1,1)
    face_list[#face_list+1] = table_append(C,1,0)
    face_list[#face_list+1] = table_append(G,0,0)
    face_list[#face_list+1] = table_append(G,0,0)
    face_list[#face_list+1] = table_append(H,0,1)
    face_list[#face_list+1] = table_append(D,1,1)
    
    face_list[#face_list+1] = table_append(E,0,1)
    face_list[#face_list+1] = table_append(H,1,1)
    face_list[#face_list+1] = table_append(G,1,0)
    face_list[#face_list+1] = table_append(G,1,0)
    face_list[#face_list+1] = table_append(F,0,0)
    face_list[#face_list+1] = table_append(E,0,1)
    
    face_list[#face_list+1] = table_append(H,0,0)
    face_list[#face_list+1] = table_append(E,1,0)
    face_list[#face_list+1] = table_append(A,1,1)
    face_list[#face_list+1] = table_append(A,1,1)
    face_list[#face_list+1] = table_append(D,0,1)
    face_list[#face_list+1] = table_append(H,0,0)
    
    face_list[#face_list+1] = table_append(C,0,0)
    face_list[#face_list+1] = table_append(B,1,0)
    face_list[#face_list+1] = table_append(F,1,1)
    face_list[#face_list+1] = table_append(F,1,1)
    face_list[#face_list+1] = table_append(G,0,1)
    face_list[#face_list+1] = table_append(C,0,0)
    
    return face_list
end

function quinta.pCube(sw,sh,sd)
    return quinta.pCubeMinMax(
        -sw/2, -sh/2, -sd/2, --min
        sw/2, sh/2, sd/2 --max
        )
end

local function createDoubleFaced(face_list)
    local i = 1
    local initial_face_num = #face_list
    --to create the inside part, we just change the 
    --face vertex order from ccw to cw
    while i < initial_face_num do
        face_list[#face_list+1] = face_list[i]
        face_list[#face_list+1] = face_list[i+2]
        face_list[#face_list+1] = face_list[i+1]
        i=i+3
    end
    
    return face_list
end

function quinta.pPlaneDF(sw,sh)
    --a cube is composed of 12 triangles
    --and 8 vertex, and later append their uv coords
    local face_list = createDoubleFaced(quinta.pPlane(sw,sh))
    
    return face_list
end

--a cube that is render also inside...
--DF is for Double Faced
function quinta.pCubeDF(sw,sh,sd)
    --a cube is composed of 12 triangles
    --and 8 vertex, and later append their uv coords
    local face_list = createDoubleFaced(quinta.pCube(sw,sh,sd))
    
    
    return face_list
end

function quinta.colAABB(sw,sh,sd)
    local self = quinta.Space3D()
    self.pos = CPMLF_NEW_VEC3(0,0,0)
    self.scale = CPMLF_NEW_VEC3(sw,sh,sd) --the size of the bounding box is equal to the scale
    self.offset = CPMLF_NEW_VEC3(0,0,0)
    self.transform = nil 
    self.color = {1,0,0,1}
    self.orig_min = CPMLF_NEW_VEC3(-sw/2, -sh/2, -sd/2)
    self.orig_max = CPMLF_NEW_VEC3(sw/2, sh/2, sd/2)
    self.min = self.orig_min
    self.max = self.orig_max
    self.is_on_chunks = {}
    self.cube_mesh = nil
    self.second_color = {0,1,1,1}
    
    function self.setSecondColor(r,g,b,a)
        self.second_color[1] = r or 1
        self.second_color[2] = g or 1
        self.second_color[3] = b or 1
        self.second_color[4] = a or 0.5
    end
    
    function self.buildNewCubeMesh()
        self.cube_mesh = quinta.newMesh(
          quinta.pCubeMinMax(self.min.x*(-1),self.min.y,self.min.z,
            self.max.x*(-1),self.max.y,self.max.z)
            )
    end
    
    function self.setColor(r,g,b,a)
        self.color[1] = r or 1
        self.color[2] = g or 1
        self.color[3] = b or 1
        self.color[4] = a or 0.5
    end
    
    function self.calculateTransform()
        --move the model...
        local new_transform = nil
        new_transform = CPMLF_IDENTITY_MATRIX()
        
        new_transform:scale(new_transform, self.scale)
        new_transform:translate(new_transform, CPMLF_NEW_VEC3(self.pos.x,self.pos.y,self.pos.z))
        
        self.transform = TransposeMatrix(new_transform)
        
        self.min = (new_transform*self.orig_min)
        self.max = (new_transform*self.orig_max)
    end
    
    self.calculateTransform()
    
    function self.intersectAABB(other)
        return cpml.intersect.aabb_aabb(self,other)
    end
    
    --this is similar to the renderMe method on the instance 3D, but more simple
    function self.renderMe(shader, renderWidth,renderHeight)
        local mesh = DEFAULT_CUBE_MODEL.meshes[1]
    
        love.graphics.setColor(self.color[1],self.color[2],self.color[3],self.color[4])
        love.graphics.setMeshCullMode('back') --back
        love.graphics.setWireframe(true) --self.wireframe
        
        if not self.cube_mesh then 
            shader:send("Model_Matrix", self.transform)
            --render only the vertex of the material...
            DEFAULT_CUBE_MODEL.mesh:setDrawRange(mesh.first, mesh.last)
            love.graphics.draw(DEFAULT_CUBE_MODEL.mesh, -renderWidth/2, -renderHeight/2)
        else
            shader:send("Model_Matrix", CPMLF_IDENTITY_MATRIX())
            self.cube_mesh:setDrawRange(mesh.first, mesh.last)
            love.graphics.draw(self.cube_mesh, -renderWidth/2, -renderHeight/2)
        end
        love.graphics.setMeshCullMode("none")
        
        love.graphics.setWireframe(false)
    end
    
    return self
end

--A samll triange for colision detection
--this is for static bodys
function quinta.colTriangleMStatic(new_a,new_b,new_c)
    local self = {}
    self.triangle = {new_b,new_a,new_c}
    
    local min_x = MIN(MIN(new_a.x,new_b.x),new_c.x)
    local min_y = MIN(MIN(new_a.y,new_b.y),new_c.y)
    local min_z = MIN(MIN(new_a.z,new_b.z),new_c.z)
    
    local max_x = MAX(MAX(new_a.x,new_b.x),new_c.x)
    local max_y = MAX(MAX(new_a.y,new_b.y),new_c.y)
    local max_z = MAX(MAX(new_a.z,new_b.z),new_c.z)
    
    self.min = CPMLF_NEW_VEC3(min_x,min_y,min_z)
    self.max = CPMLF_NEW_VEC3(max_x,max_y,max_z)
    
    function self.intersectAABB(other)
        return cpml.intersect.aabb_aabb(self,other)
    end
    
    return self
end

function quinta.colTriangle(vertex_a,vertex_b, vertex_c)
    local self = quinta.colAABB(1,1,1)
    self.transform = nil 
    self.color = {1,0,1,1}
    
    
    --a cube is composed of 12 triangles
    --and 8 vertex, and later append their uv coords
    self.triangle = {vertex_a,vertex_b,vertex_c}
    
    function self.buildNewTriangleMesh()
        local a = self.triangle[1]
        local b = self.triangle[2]
        local c = self.triangle[3]
        a.x = a.x*(-1)
        b.x = b.x*(-1)
        c.x = c.x*(-1)
        self.triangle_mesh = quinta.newMesh(
           quinta.pTriangleFromVectors(a,b,c)
            )
        a.x = a.x*(-1)
        b.x = b.x*(-1)
        c.x = c.x*(-1)
    end
    
    
    function self.calculateTransform()
        --move the model...
        local new_transform = nil
        new_transform = CPMLF_IDENTITY_MATRIX()
        
        new_transform:scale(new_transform, self.scale)
        
        new_transform:rotate(new_transform, self.rot.z , CPMLC_UNIT_V3_Z)
        new_transform:rotate(new_transform, -self.rot.y , CPMLC_UNIT_V3_Y)
        new_transform:rotate(new_transform, self.rot.x , CPMLC_UNIT_V3_X)
        
        new_transform:translate(new_transform, CPMLF_NEW_VEC3(self.pos.x,self.pos.y,self.pos.z))
        
        self.transform = TransposeMatrix(new_transform)
        local new_a = (new_transform*vertex_a)
        local new_b = (new_transform*vertex_b)
        local new_c = (new_transform*vertex_c)
        self.triangle = {new_b,new_a,new_c}
        
        --calculate a new bounding box for the plane
        local min_x = MIN(MIN(new_a.x,new_b.x),new_c.x)
        local min_y = MIN(MIN(new_a.y,new_b.y),new_c.y)
        local min_z = MIN(MIN(new_a.z,new_b.z),new_c.z)
        
        local max_x = MAX(MAX(new_a.x,new_b.x),new_c.x)
        local max_y = MAX(MAX(new_a.y,new_b.y),new_c.y)
        local max_z = MAX(MAX(new_a.z,new_b.z),new_c.z)
        
        self.min = CPMLF_NEW_VEC3(min_x,min_y,min_z)
        self.max = CPMLF_NEW_VEC3(max_x,max_y,max_z)
        
        --flip the x value for the render...
        
    end
    
    self.calculateTransform()
    --self.buildNewTriangleMesh()
    
    --this is similar to the renderMe method on the instance 3D, but more simple
    local old_renderMe = self.renderMe 
    self.renderMe = function(shader, renderWidth,renderHeight)
        
        self.buildNewTriangleMesh() --create a new mesh for the triangle
        self.buildNewCubeMesh() 
        
        old_renderMe(shader, renderWidth,renderHeight)
        local mesh = DEFAULT_PLANE_MODEL.meshes[1]
        --this is horrible... 
        love.graphics.setMeshCullMode('back') --back
        shader:send("Model_Matrix", CPMLF_IDENTITY_MATRIX())
        self.triangle_mesh:setDrawRange(mesh.first, mesh.last)
        
        love.graphics.setWireframe(true) --self.wireframe
        love.graphics.setColor(self.second_color[1],self.second_color[2],self.second_color[3],self.second_color[4])
        love.graphics.draw(self.triangle_mesh, -renderWidth/2, -renderHeight/2)
        
        love.graphics.setMeshCullMode("none")
        
        love.graphics.setWireframe(false)
    end
    
    return self
end

--we use the reiange colision
function quinta.colPlane(sw,sh)
    local self = quinta.colAABB(sw,sh,1)
    self.transform = nil 
    self.color = {0,1,0,0.25}
    
    --a cube is composed of 12 triangles
    --and 8 vertex, and later append their uv coords
    self.triangles = {}
    self.plane_mesh = nil
    
    local x0,y0 = -0.5, -0.5
    local x1,y1,z1 = 0.5, 0.5, 0
    
    local vertex_a = CPMLF_NEW_VEC3(x1, y0, z1)
    local vertex_b = CPMLF_NEW_VEC3(x0, y0, z1)
    local vertex_c = CPMLF_NEW_VEC3(x0, y1, z1)
    local vertex_d = CPMLF_NEW_VEC3(x1, y1, z1)
    self.triangles[1] = {vertex_b,vertex_a,vertex_c}
    self.triangles[2] = {vertex_d,vertex_c,vertex_a}
    
    
    
    function self.buildNewPlaneMesh()
        local a = self.triangles[1][3]
        local b = self.triangles[1][2]
        local c = self.triangles[1][1]
        local d = self.triangles[2][2]
        
        a.x = a.x*(-1)
        b.x = b.x*(-1)
        c.x = c.x*(-1)
        d.x = d.x*(-1)
        self.plane_mesh = quinta.newMesh(
           createDoubleFaced(quinta.pPlaneFromVectors(a,b,c,d))
            )
        a.x = a.x*(-1)
        b.x = b.x*(-1)
        c.x = c.x*(-1)
        d.x = d.x*(-1)
    end
    
    function self.calculateTransform()
        --move the model...
        local new_transform = nil
        new_transform = CPMLF_IDENTITY_MATRIX()
        
        new_transform:scale(new_transform, self.scale)
        
        new_transform:rotate(new_transform, self.rot.z , CPMLC_UNIT_V3_Z)
        new_transform:rotate(new_transform, -self.rot.y , CPMLC_UNIT_V3_Y)
        new_transform:rotate(new_transform, self.rot.x , CPMLC_UNIT_V3_X)
        
        new_transform:translate(new_transform, CPMLF_NEW_VEC3(self.pos.x,self.pos.y,self.pos.z))
        
        self.transform = TransposeMatrix(new_transform)
        local new_a = (new_transform*vertex_a)
        local new_b = (new_transform*vertex_b)
        local new_c = (new_transform*vertex_c)
        local new_d = (new_transform*vertex_d)
        self.triangles[1] = {new_c,new_b,new_a}
        self.triangles[2] = {new_a,new_d,new_c}
        
        --calculate a new bounding box for the plane
        local min_x = MIN(MIN(MIN(new_a.x,new_b.x),new_c.x),new_d.x)
        local min_y = MIN(MIN(MIN(new_a.y,new_b.y),new_c.y),new_d.y)
        local min_z = MIN(MIN(MIN(new_a.z,new_b.z),new_c.z),new_d.z)
        
        local max_x = MAX(MAX(MAX(new_a.x,new_b.x),new_c.x),new_d.x)
        local max_y = MAX(MAX(MAX(new_a.y,new_b.y),new_c.y),new_d.y)
        local max_z = MAX(MAX(MAX(new_a.z,new_b.z),new_c.z),new_d.z)
        
        self.min = CPMLF_NEW_VEC3(min_x,min_y,min_z)
        self.max = CPMLF_NEW_VEC3(max_x,max_y,max_z)
         --create a new box for the cube
    end
    
    self.calculateTransform()
    --this is similar to the renderMe method on the instance 3D, but more simple
    local old_renderMe = self.renderMe 
    self.renderMe = function(shader, renderWidth,renderHeight)
        self.buildNewPlaneMesh()
        self.buildNewCubeMesh()
        
        old_renderMe(shader, renderWidth,renderHeight)
        local mesh = DEFAULT_PLANE_MODEL.meshes[1]
        --this is horrible... 
        love.graphics.setMeshCullMode('back') --back
        shader:send("Model_Matrix", CPMLF_IDENTITY_MATRIX())
        self.plane_mesh:setDrawRange(mesh.first, mesh.last)
        
        love.graphics.setWireframe(true) --self.wireframe
        love.graphics.setColor(self.second_color[1],self.second_color[2],self.second_color[3],self.second_color[4])
        love.graphics.draw(self.plane_mesh, -renderWidth/2, -renderHeight/2)
        
        love.graphics.setMeshCullMode("none")
        
        love.graphics.setWireframe(false)
    end
    
    return self
end

function quinta.Camera(camera_type, renderWidth, renderHeight)
    local self = quinta.Space3D()
    local fov = 60
    local nearClip = 0.0001
    local farClip = 1000
    local width, height = love.window.getMode( )
    self.renderHeight = renderHeight or height
    self.renderWidth = renderWidth or width
    self.direction = CPMLF_NEW_VEC3(0,0,-1) --by default, the camera is downward
    self.camera_dir_transform = nil
    self.scale = CPMLF_NEW_VEC3(1,1,1)
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
    
    --we override the calculte transform of space3D
    function self.calculateTransform()
        --move the model...
        local new_transform = nil
        new_transform = CPMLF_IDENTITY_MATRIX()
        
        -- apply rotations
        new_transform:scale(new_transform, self.scale)

        new_transform:rotate(new_transform, self.rot.z , CPMLC_UNIT_V3_Z)
        new_transform:rotate(new_transform, self.rot.y , CPMLC_UNIT_V3_Y)
        new_transform:rotate(new_transform, self.rot.x , CPMLC_UNIT_V3_X)
        
        new_transform:translate(new_transform, CPMLF_NEW_VEC3(self.pos.x,self.pos.y,self.pos.z))

        self.camera_dir_transform = TransposeMatrix(new_transform)

        new_transform = CPMLF_IDENTITY_MATRIX()
        new_transform:translate(new_transform, CPMLF_NEW_VEC3(0,0,0))
        -- apply rotations
        new_transform:rotate(new_transform, -self.rot.x , CPMLC_UNIT_V3_X)
        new_transform:rotate(new_transform, self.rot.y , CPMLC_UNIT_V3_Y)
        new_transform:rotate(new_transform, self.rot.z , CPMLC_UNIT_V3_Z)
        --]]
        self.direction = (new_transform*(CPMLF_NEW_VEC3(0,0,-1)))
    end
    
    self.calculateTransform()


    function  self.lookAt(target)
        local v2d_1 = CPMLF_NEW_VEC2(self.pos.x,self.pos.y)
        local v2d_trg = CPMLF_NEW_VEC2(target.pos.x,target.pos.y)
        local angle = CPMLF_VEC2_ANGLE2(v2d_1,v2d_trg )
        local angle2 = math.atan2( CPMLF_VEC2_DIST(v2d_1,v2d_trg), self.pos.z-target.pos.z )
        
        self.rot.z = angle-math.rad(90)
        self.rot.x = angle2
    end

    function self.calculateViewMatrix()
        self.camera_view = cpml.mat4()
        self.camera_view:translate(self.camera_view, CPMLF_NEW_VEC3(self.pos.x,-self.pos.y,-self.pos.z))
    
        self.camera_view:rotate(self.camera_view, self.rot.z, CPMLC_UNIT_V3_Z)
        self.camera_view:rotate(self.camera_view, self.rot.y, CPMLC_UNIT_V3_Y)
        self.camera_view:rotate(self.camera_view, self.rot.x, CPMLC_UNIT_V3_X)
        self.camera_view = TransposeMatrix(self.camera_view)
    end            
    


    return self
end

function quinta.Instance3D()
    local self = quinta.Space3D()
    self.model = nil
    self.culling = 'back'
    
    self.materials = nil 
    self.transform = nil
    self.model_rot_transform = nil
    self.wireframe = false
    self.color = {1,1,1,1}
    self.animation = nil
    
    --this sets the color of tint, it does not change the vertex color
    function self.setColor(r,g,b,a)
        self.color[1] = r or 1
        self.color[2] = g or 1
        self.color[3] = b or 1
        self.color[4] = a or 1
    end
    
    function  self.setWireframe(val)
        self.wireframe = val or false
    end

    --we defined this function is to tranform the mesh to be draw
    function self.calculateTransform()
        --move the model...
        local new_transform = nil
        new_transform = CPMLF_IDENTITY_MATRIX()
        
        -- apply rotations
        new_transform:scale(new_transform, self.scale)

        new_transform:rotate(new_transform, self.rot.z , CPMLC_UNIT_V3_Z)
        new_transform:rotate(new_transform, self.rot.y , CPMLC_UNIT_V3_Y)
        new_transform:rotate(new_transform, self.rot.x , CPMLC_UNIT_V3_X)
        
        new_transform:translate(new_transform, CPMLF_NEW_VEC3(-self.pos.x,self.pos.y,self.pos.z))

        self.transform = TransposeMatrix(new_transform)

        new_transform = CPMLF_IDENTITY_MATRIX()
        new_transform:translate(new_transform, CPMLF_NEW_VEC3(0,0,0))
        -- apply rotations
        new_transform:rotate(new_transform, -self.rot.x , CPMLC_UNIT_V3_X)
        new_transform:rotate(new_transform, -self.rot.y , CPMLC_UNIT_V3_Y)
        new_transform:rotate(new_transform, -self.rot.z , CPMLC_UNIT_V3_Z)

        self.model_rot_transform = new_transform
        --]]
    end

    self.calculateTransform()
    

    function self.renderMe(shader, renderWidth,renderHeight, layer)
        for _, mesh in ipairs(self.layer_meshes[layer]) do
            --this is horrible... 
            shader:send("Model_Matrix", self.transform)
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
            love.graphics.setColor(self.color[1],self.color[2],self.color[3],self.color[4])
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
        local v2d_1 = CPMLF_NEW_VEC2(self.pos.x,self.pos.y)
        local v2d_trg = CPMLF_NEW_VEC2(target.pos.x,target.pos.y)
        local angle2 = math.atan2( CPMLF_VEC2_DIST(v2d_1,v2d_trg), target.pos.z-self.pos.z )
        local new_transform = CPMLF_IDENTITY_MATRIX()
        
        --I hate the Gimbal lock problem...
        new_transform:rotate(new_transform, self.rot.y , CPMLC_UNIT_V3_Y)
        new_transform:rotate(new_transform, self.rot.x + angle2, CPMLC_UNIT_V3_X)
        new_transform:rotate(new_transform, self.rot.z + target.rot.z, CPMLC_UNIT_V3_Z)

        new_transform:translate(new_transform, CPMLF_NEW_VEC3(-self.pos.x,self.pos.y,self.pos.z))
        self.transform = TransposeMatrix(new_transform)
    end

    function self.billboardTo(target,angle)
        local angle = angle or 0
        self.rot.z = angle-target.rot.z
        self.calculateTransform()
    end

    function self.faceTo(target,nangle)
        local nangle = nangle or 0 
        local angle = CPMLF_VEC2_ANGLE2(CPMLF_NEW_VEC2(self.pos.x,-self.pos.y),CPMLF_NEW_VEC2(target.pos.x,-target.pos.y))
        self.setRot(nil,nil,nangle-angle)
    end

    function  self.lookAt(target)
        local v2d_1 = CPMLF_NEW_VEC2(self.pos.x,self.pos.y)
        local v2d_trg = CPMLF_NEW_VEC2(target.pos.x,target.pos.y)
        local angle = CPMLF_VEC2_ANGLE2(v2d_1,v2d_trg )
        local angle2 = math.atan2( CPMLF_VEC2_DIST(v2d_1,v2d_trg), self.pos.z-target.pos.z )
        local new_transform = CPMLF_IDENTITY_MATRIX()
        
        --if x then self.rot.x = x end
        --if y then self.rot.y = y end
        --if z then self.rot.z = z end
        
        --self.rot.z = angle--math.rad(90)
        --self.rot.x = angle2---math.rad(90)
        
        
        --I hate the Gimbal lock problem...
        new_transform:rotate(new_transform, self.rot.y , CPMLC_UNIT_V3_Y)
        new_transform:rotate(new_transform, self.rot.x-angle2 , CPMLC_UNIT_V3_X)
        new_transform:rotate(new_transform, self.rot.z-angle , CPMLC_UNIT_V3_Z)

        new_transform:translate(new_transform, CPMLF_NEW_VEC3(-self.pos.x,self.pos.y,self.pos.z))
        self.transform = TransposeMatrix(new_transform)
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
            self.bound = self.model.bounds[#self.model.bounds]
            --[[
            for k,v in pairs(self.model.bounds) do
                for k1,v1 in pairs(v) do
                    print('--->',k1,v1[1],v1[2],v1[3])
                end
                print('::',k)
            end
            --]]
            --self.animation = anim9(iqm.load_anims(data))
        end
    else
        --we asumed is not a path, but user mesh data
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
    local obj_pos2d = CPMLF_NEW_VEC2.new(0,0)
    local cam_dir2d = CPMLF_NEW_VEC2(0,0)
    
    local love_width, love_height = love.graphics.getDimensions( )
    local renderWidth  = resolution_x or love_width 
    local renderHeight = resolution_y or love_height  

    self.camera = quinta.Camera('perspective',renderWidth,renderHeight)
    self.shader = nil
    self.canvas = love.graphics.newCanvas( self.camera.renderWidth, self.camera.renderHeight)
    startupRender()
    self.shader = DEFAULT_SHADER
    local object_list = {}
    --this list is to add the aabb to be rendered
    local collition_list = {}
    --local light_list = {}

    --local ambientLight = 0.25

    self.light = {}
    self.light.pos = {0,0,0}
    self.light.color = {1,1,1}
    self.bgcolor = {0,0,0,1}
    self.offset_d = 0
    self.render_percent = 0

    self.heap = CHeap()
    self.heap.compare = function(a,b)
        local distance_a = CPMLF_VEC3_DIST2(self.camera.pos, a.pos)
        local distance_b = CPMLF_VEC3_DIST2(self.camera.pos, b.pos)
        return distance_a >= distance_b
    end
    
    function self.startUp()
        
    end

    --function self.addLight(light)
    --    table.insert(object_list,object)
    --end

    function self.addObject(object)
        local i = 1
        while object_list[i] do
            if object_list[i] == object then
                return
            end
            i=i+1
        end
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
            i=i+1
        end
    end
    
    
    
    --clear all the objects of the current render list
    function self.clearObjects()
        object_list = {}
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
    function self.setBackgroundColor(r,g,b,a)
        self.bgcolor[1] = r or 0
        self.bgcolor[2] = g or 0
        self.bgcolor[3] = b or 0
        self.bgcolor[4] = a or 1
    end

    function self.render()
        
        love.graphics.setCanvas({self.canvas, depth=true})
        
            love.graphics.clear(self.bgcolor[1],self.bgcolor[2],self.bgcolor[3],self.bgcolor[4])

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
