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
    --print(msg)
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

-- dump a table, for debug
function dump(t, level)
  level = level or 0
  for i,v in pairs(t) do
    io.write(string.rep('  ', level))
    io.write(i..': ')
    if type(v) == 'table' then
      print ''
      dump(v, level + 1)
    else
      print(tostring(v))
    end
  end
end

--[[
  Create a filesystem.

  @return {boolean} - success or failure
]]
cext.createFS = function(this, location, size)
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

  if fs.exists(filesystem) ~= true then
    return nil, "ERRNOTFOUND"
  end

  -- load the raw filesystem.
  local iohandle     = fs.open(filesystem, "r")
  this.fs.superblock = iohandle.readLine() -- read the first line, the superblock.
  this.fs.inodes_str     = iohandle.readLine() -- read the second line, the inodes.
  this.fs.data       = iohandle.readAll()  -- read the rest, this is data.
  iohandle.close()

  local fs_length = ""
  if this.fs.data ~= nil then
    local l = string.split(this.fs.data, "\n")

    local ii = 0
    for i,v in pairs(l) do
      ii = i;
    end

    fs_length = ii+3
  end

  -- parse the superblock
  local superblockSplit = string.split(this.fs.superblock, ",")

  -- assign it to the table.
  this.fs.superblock = {}
  this.fs.superblock.version = superblockSplit[1]
  this.fs.superblock.inodes = superblockSplit[2]
  this.fs.superblock.size = superblockSplit[3]
  this.fs.superblock.nextContents = superblockSplit[4]

  -- this.print("superblock.version       = "..tostring(superblockSplit[1]))
  -- this.print("superblock.inodes        = "..tostring(superblockSplit[2]))
  -- this.print("superblock.size          = "..tostring(superblockSplit[3]))
  -- this.print("superblock.nextContents  = "..tostring(superblockSplit[4]))

  -- DATA CHECK
  if tostring(fs_length) ~= tostring(this.fs.superblock.nextContents) then
    print("WARNING: DATA FOUND AFTER BLOCK, DATA LOSS MAY OCCUR")
    print(fs_length.." ~= "..this.fs.superblock.nextContents)
  end

  -- parse the inode line.
  this.fs.inodes = {}
  this.fs.inodes.isDir = "1"
  local stat, err = this:parseInode(this.fs.inodes_str)

  if err or stat == false then
    print("cext: failed to load")
    print("Err: "..tostring(err))
    error("ERRFAILEDTOLOAD") -- critical error
  end

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

    if inode[2] ~= nil then
      this.print("pre-inode: "..inode[2])
      this:addInode("", inode[2], inode[3], inode[4], inode[5])
    end
  end
end

--[[
  Add an inode to the table.

  @return {boolean} - true on success
]]
cext.addInode = function(this, filelocation, filename, min, max, dir)

  -- check if sub is object
  if this.fs.inodes[filelocation] == nil then
    this.fs.inodes[filelocation] = {}
  end

  this.print("cext: create inode for "..fs.combine(filelocation, filename))

  function recurv_dir(this, d)
    local s = ""
    local dirs = string.split(d, "/")
    for i,v in pairs(dirs) do
      s = fs.combine(s, v)
      this.print(d..": mkdir for "..v)
      this:makeDir(s)
    end
  end

  local obj = {}
  obj.min = min
  obj.max = max
  obj.filename = filename
  obj.isDir = tostring(dir) -- is not a directory
  obj.parent = filelocation

  if filelocation == "" or tostring(dir) == "1" then -- root dir stuff.
    this.fs.inodes[filename] = obj
  else
    this.print(filelocation.." +> "..filename)
    this.fs.inodes[fs.combine(filelocation, filename)] = obj
    recurv_dir(this, filelocation)
  end

  return true
end

--[[
  Serialize a inode object back into an inode table.

  @return {string} - inode table.
]]
cext.serializeInode = function(this, object)
  local inode = ""

  local function _wi(index, value)
    if value.parent == nil then -- empty indexs
      this.print("cext: invalid inode on <root>['"..index.."']")
      return
    end

    -- generate the inode string
    inode = inode ..
    value.parent ..     "," ..
    index ..            "," ..
    value.min ..        "," ..
    value.max ..        "," ..
    value.isDir ..      "\\"
  end

  for i, v in pairs(this.fs.inodes) do
    _wi(i, v, "")
  end

  this.print(inode);
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

  this.print("cext: synced to disk.")

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
    max = max+1 -- up by one
    local n = this.fs.superblock.nextContents+(i-3)

    if i == #nl then
      -- this.print("cext: write: i is nl len. call asm.")
      this:writeToLine(n, v, true)
    else
      this:writeToLine(n, v)
    end
  end

  -- write the new inode to the actual line.
  this:addInode(fileLocation, fileName, min, max, "0")

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
    -- this.print("cext: told to assemble the table into a string")
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
  if this:isDir(file) then
    return nil, "ISDIR"
  end

  local inode = this.fs.inodes[file]

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
    if i > (min-2) and i < (max-2) or i == (min-2) then -- bad algo is bad
      if (i+2) > (max-2) then
        d = d..v
      else
        d = d..v.."\n"
      end
    end
  end

  return d
end

--[[
  Get the contents of a directory

  @return {table} - of contents
]]
cext.list = function(this, path)
  if this:isDir(path) == false then
    print("Is not a DIR")
    return nil, "ERRNOTADIR"
  end

  if this.fs.inodes == nil then
    return nil, "ERRNOROOT"
  end

  local t = {}
  local canonical_path = this.fs.inodes

  if canonical_path == nil then -- doesn't exist
    return nil, "ERRNOTEXIST"
  end

  for i,v in pairs(canonical_path) do
    if v.parent == path then
      table.insert(t, fs.getName(i))
    end
  end

  return t
end

--[[
  Check if it is a directory.
]]
cext.isDir = function(this, path)
  if path == "" then
    canonical_path = this.fs.inodes
  else
    canonical_path = this.fs.inodes[path]
  end

  -- dump(canonical_path)

  if canonical_path == nil then
    return false, "ERRNOTEXIST"
  elseif canonical_path.isDir ~= "1" then -- doesn't exist
    return false, "WARNNOTDIRECTORY"
  end

  return true, "ISDIR"
end

--[[
  Check if the file exists

  @return true, or nil
]]

cext.exists = function(this, path)
  if path == "" then
    canonical_path = this.fs.inodes
  else
    canonical_path = this.fs.inodes[path]
  end

  if canonical_path == nil then
    return nil
  end

  return true
end

--[[
  Make a directory

  @return nil
]]
cext.makeDir = function(this, path)
  this.fs.inodes[path] = {}
  this.fs.inodes[path].min = "0"
  this.fs.inodes[path].max = "0"
  this.fs.inodes[path].filename = fs.getName(path)
  this.fs.inodes[path].isDir = "1" -- is not a directory
  this.fs.inodes[path].parent = tostring(fs.getDir(path))

  return nil
end


-- TESTING
fs.delete("/cext/test.fs")
cext:createFS("/cext/test.fs", 1000)
cext:open("/cext/test.fs")
cext:write("nothing", "ignore me data")
cext:close()
cext:open("/cext/test.fs")
cext:write("a/dir/ccdocker", fs.open("/cext/ccdocker", "r").readAll())
cext:close()

if cext:isDir("") then
  print("root is a dir... good")
else
  print("root is not a dir... bad")
end

local c,r  = cext:isDir("a/dir/ccdocker")
if c then
  print("regular file is a dir... bad")
else
  print("ccdocker is not a dir... good!")
end

local tbl, err = cext:list("a/dir")
if err then
  print("Err: "..err)
end

--[[for i,v in pairs(tbl) do
  print(v)
end]]

cext:open("/cext/test.fs")
