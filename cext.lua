--[[
  A lightweight ext-like FS implemented in pure lua.

  Specs: <insert link here>

  @author Jared Allard <jaredallard@outlook.com>
  @license MIT
  @notice uses JSDoc like insource documention.
]]

-- intial declearation of the FS table.
local cext = {
  ["version"] = 011,
  ["date"]    = 20150530,
  ["print"] = function(msg)
    print(msg)
    return nil -- no output
  end,
  ["fs"] = nil, -- assurance.
}

-- temporary.

-- split a string
function string.split(s, delimiter)
    result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end


--[[
  Create a filesystem.

  @return {boolean} - success or failure
]]
cext.createFS = function(this, location, size)
  -- this.checkArgs(this, size)

  -- superblockHeader.
  local superblockHeader = this.version..",0,"..size
  local inodeAllocation = ""

  -- remove a stale filesystem.
  if fs.exists(location) then
    this.print("removing stale fs")
    fs.delete(location)
  end

  local inodes = "empty"

  -- open a io file handle and inject the superblockHeader & inodeAllocation ws.
  local iohandle = io.open(location, "w")
  iohandle:write(superblockHeader..",3\n"..inodes.."\n") -- three whitespace lines.
  iohandle:close()

  -- return true since we probably had no issues.
  return true
end

--[[
  Open the file system (essentially load it into memory)

  @return {boolean} - success or fail.
]]
cext.open = function(this, filesystem)
  -- give the fs object an initial start.
  this.fs = {
    ["superblock"] = nil,
    ["data"]       = nil,
    ["inodes"]     = nil,
    ["path"]       = nil,
  }

  -- load the raw filesystem.
  local iohandle     = fs.open(filesystem, "r")
  this.fs.superblock = iohandle.readLine() -- read the first line, the superblock.
  this.fs.inodes     = iohandle.readLine() -- read the second line, the inodes.
  this.fs.data       = iohandle.readAll()  -- read the rest, this is data.
  iohandle.close()

  -- parse the superblock
  local superblockSplit = string.split(this.fs.superblock, ",")

  -- assign it to the table.
  this.fs.superblock = {}
  this.fs.superblock.version = superblockSplit[1]
  this.fs.superblock.inodes = superblockSplit[2]
  this.fs.superblock.size = superblockSplit[3]
  this.fs.superblock.nextContents = superblockSplit[4]

  this.print("superblock.version       = "..tostring(superblockSplit[1]))
  this.print("superblock.inodes        = "..tostring(superblockSplit[2]))
  this.print("superblock.size          = "..tostring(superblockSplit[3]))
  this.print("superblock.nextContents  = "..tostring(superblockSplit[4]))

  -- parse the inode line.
  this.fs.inodes = this:parseInode(this.fs.inodes)

  -- probably no errors, so set the path.
  this.fs.path = filesystem

  this.print('opened cext filesystem version: '..this.fs.superblock.version)

  -- return true as we probably had no issues.
  return true
end

--[[
  Parse an inode block into an object.

  @return {object} - inodes in an object
]]
cext.parseInode = function(this, serialized)
  if serialized == "empty" then
    this.print("inode table reports empty")
    -- return an empty table.
    return {}
  end

  local filenames = string.split(serialized, "\\")
  local tbl = {}

  for i, v in ipairs(filenames) do
    local inode = string.split(v, ",")

    if tbl[inode[1]] == nil then
      this.print("creating directory ")
      tbl[inode[1]] = {}
    end

    if inode[2] ~= nil then
      -- add it to the table.
      tbl[inode[1]][inode[2]] = {}
      tbl[inode[1]][inode[2]].min = inode[3]
      tbl[inode[1]][inode[2]].max = inode[4]
    end
  end

  return tbl
end

--[[
  Add an inode to the table.

  @return {boolean} - true on success
]]
cext.addInode = function(this, filelocation, filename, min, max, typeof)
  if this.fs.inodes[filelocation] == nil then
    this.fs.inodes[filelocation] = {}
  end

  if typeof == nil then
    typeof = "file"
  end

  local dlm = string.split(filelocation, "/")
  local stack = ""
  for i, v in ipairs(dlm) do
    if i ~= 1 then
      stack = stack .. "/" .. v
    else
      stack = stack .. v
    end

    if this.fs.inodes[stack] == nil then
      this.fs.inodes[stack] = {}
    end

    -- create the virtual link
    this.fs.inodes[stack][v] = {}
    this.fs.inodes[stack][v].dir = true
    print(stack)
  end

  this.fs.inodes[filelocation][filename] = {}
  this.fs.inodes[filelocation][filename].min = min
  this.fs.inodes[filelocation][filename].max = max

  return true
end

--[[
  Serialize a inode object back into an inode table.

  @return {string} - inode table.
]]
cext.serializeInode = function(this, object)
  local inode = ""

  local function _wi(index, value, stack)
    if type(value) ~= "table" then
      return 2 -- entered inode territory
    end

    for i, v in pairs(value) do
      local i = _wi(i, v, stack.."/"..i)

      if i == 2 then
        -- generate an inode
        this.print("generate an inode for "..index)


        -- ignore the virtual directory symlink
        if value.dir ~= true then
          inode = inode ..
          fs.getDir(stack) ..     "," ..
          index ..     "," ..
          value.min .. "," ..
          value.max .. "\\"
        end

        break
      end
    end
  end

  for i, v in pairs(this.fs.inodes) do
    _wi(i, v, "")
  end

  return inode
end

--[[
  Close the filesystem. (write to disk)

  @return {boolean} - success or fail
]]
cext.close = function(this)
  local superblock = this.fs.superblock.version..","..this.fs.superblock.inodes..
    ","..this.fs.superblock.size..","..
    this.fs.superblock.nextContents

  local data = this.fs.data

  -- create the final object of the fs.
  local filesystem = superblock.."\n"..this:serializeInode(this.fs.inodes).."\n"..data

  local fshandle = fs.open(this.fs.path, "w")
  fshandle.write(filesystem)
  fshandle.close()

  this.print("cext: this.fs.data_table = "..tostring(this.fs.data_table))

  return true
end

--[[
  Write to the filesystem

  @return {boolean} - success or fail, if fail then error message
    on second param return.
]]
cext.write = function(this, filename, data)
  if this.fs == nil then
    error("fs isn't loaded. load with this:open(fs)")
  end

  local fileLocation = fs.getDir(filename)
  local fileName     = fs.getName(filename)

  -- write the filecontents.
  local nl = string.split(data, "\n")
  local min = this.fs.superblock.nextContents
  local max = min

  this.print("write: fl="..fileLocation.." fn: "..fileName)

  for i, v in pairs(nl) do
    max = max+1
    local n = this.fs.superblock.nextContents+(i-1)

    if i == #nl then
      this.print("cext: write: i is nl len. call asm.")
      this:writeToLine(n, v, true)
    else
      this:writeToLine(n, v)
    end
  end

  -- print it out for now.
  this.print(inodeObject)

  -- write the new inode to the actual line.
  this:addInode(fileLocation, fileName, min, max)

  -- increment the amount of content lines
  this.fs.superblock.nextContents = max

  return true
end

--[[
  Write to a line in the filesystem cache.

  @return {boolean} - success or fail.
]]
cext.writeToLine = function(this, line, data, asm)
  -- check if we've already been called. We should sync on asm = true
  if this.fs.data_table == nil then
    this.fs.data_table = string.split(this.fs.data, "\n")
  end

  -- write to the line, this is a very fragile operation
  this.fs.data_table[tonumber(line)] = data

  if asm == true then
    this.print("cext: told to assemble the table into a string")
    -- convert the table into a string.
    local d = ""
    for i,v in pairs(this.fs.data_table) do
      d = d..v.."\n"
    end

    -- set the string as the new data object.
    this.fs.data = tostring(d)

    -- invalidate the table.
    this.fs.data_table = nil
  end

  -- since we are stil here, we had a successful write.
  return true
end

--[[
  Read the contents of a file.

  @return {string} - file contents, or nil on failure.
]]
cext.read = function(this, file)
  local fl = fs.getDir(file)
  local fn = fs.getName(file)

  if this.fs.inodes[fl][fn] == nil then
    this.print("file not found")
    return nil
  end

  local inode = this.fs.inodes[fl][fn]

  this.print("contents are on: "..inode.min.."-"..inode.max)

  return this:readLines(inode.min.."-"..inode.max)
end

cext.readLines = function(this, linesep)
  local nl = string.split(this.fs.data, "\n")
  local m = string.split(linesep, '-')
  local min = tonumber(m[1])
  local max = tonumber(m[2])

  local d = ""
  for i,v in pairs(nl) do
    if i > min and i < max then
      d = d..v.."\n"
    end
  end

  if d == "" then
    return false
  end

  return d
end

--[[
  Get the contents of a directory

  @return {table} - of contents
]]
cext.list = function(this, path)
  if this:isDir(path) == false then
    return nil
  end

  if this.fs.inodes[path] == nil then -- doesn't exist
    return nil
  end

  local t = {}
  for i,v in pairs(this.fs.inodes[path]) do
    print(i)
    table.insert(t, i)
  end

  return t
end

--[[
  Check if it is a directory.
]]
cext.isDir = function(this, path)
  if this.fs.inodes[path] == nil then -- doesn't exist
    return false
  elseif this.fs.inodes[path].max ~= nil then -- not a file
    this.print("is a file")
    return false
  end

  return true
end

--[[
  Make a directory

  @return nil
]]
cext.makeDir = function(this, path)
  if this.fs.inodes[path] == nil then
    this.fs.inodes[path] = nil
  end

  return nil
end


-- TESTING
fs.delete("test.fs")
cext:createFS("test.fs", 1000)
cext:open("test.fs")
cext:write("nothing", "hacky fix")
cext:close()

cext:open("test.fs")
cext:write("a/dir/ccdocker", fs.open("ccdocker", "r").readAll())
cext:close()

--cext:open("test.fs")
-- cext:read("ccdocker")

if cext:isDir("") then
  print("root is a dir")
else
  print("root is not a dir, bad")
end

if cext:isDir("ccdocker") then
  print("regular file is a dir... bad")
else
  print("ccdocker is not a dir... good!")
end

for i, v in pairs(cext:list("")) do
  print(i..": "..v)
end
