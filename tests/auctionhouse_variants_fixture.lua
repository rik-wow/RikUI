-- Models the native TableBuilder column/pool lifecycle, including release before reuse.
local fixture = require("auctionhouse_fixture")
local variants = {}
function variants.Pool(_, _, _, reset, _, postCreate)
    local pool = { active = {}, inactive = {}, created = 0 }
    function pool:Acquire()
        local cell = table.remove(self.inactive)
        if not cell then
            cell = fixture.Frame()
            self.created = self.created + 1
            postCreate(cell)
            reset(self, cell, true)
        end
        self.active[cell] = true
        return cell
    end
    function pool:Release(cell)
        assert(self.active[cell], "release must belong to this pool")
        reset(self, cell)
        self.active[cell] = nil
        table.insert(self.inactive, cell)
    end
    return pool
end
function variants.List(list)
    local builder = { columns = {}, rows = {}, arranged = 0 }
    function builder:GetColumns() return self.columns end
    function builder:AddColumn()
        local column = { cells = {}, args = {} }
        function column:ConstructHeader(_, _, owner, text, sort)
            self.header = fixture.Frame(list.HeaderContainer, "VariantHeader", "Button")
            self.header.owner, self.header.text, self.header.sort = owner, text, sort
        end
        function column:SetFillConstraints(value, padding) self.fill, self.padding = value, padding end
        function column:SetFixedConstraints(value, padding) self.width, self.fill, self.padding = value, nil, padding end
        function column:SetCellPadding(left, right) self.left, self.right = left, right end
        function column:ConstructCell(row, data)
            local cell = self.pool:Acquire()
            self.cells[row] = cell
            if cell.Init then cell:Init(unpack(self.args)) end
            if cell.Populate then cell.rowData = data; cell:Populate(data) end
            cell:Show()
            return cell
        end
        function column:Reset()
            for row, cell in pairs(self.cells) do
                self.pool:Release(cell)
                for i, value in ipairs(row.cells) do
                    if value == cell then table.remove(row.cells, i); break end
                end
            end
            self.cells = {}
        end
        table.insert(self.columns, column)
        return column
    end
    function builder:SetTableWidth(width) self.width = width end
    function builder:Arrange()
        self.arranged = self.arranged + 1
        for _, column in ipairs(self.columns) do column:Reset() end
        for _, row in ipairs(self.rows) do
            for _, column in ipairs(self.columns) do
                if column.pool.Acquire then
                    local cell = column:ConstructCell(row, row.rowData)
                    table.insert(row.cells, cell)
                    cell:SetParent(row)
                end
            end
        end
    end
    function builder:Reset()
        for _, column in ipairs(self.columns) do column:Reset() end
        self.columns = {}
    end
    local templates = { "Bid", "Buyout", "AuctionHouseTableCellItemQuantityLeftTemplate", "ExtraInfo", "TimeLeft" }
    local function nativeLayout(b)
        for i, template in ipairs(templates) do
            local column = b:AddColumn()
            column.native = template
            column.pool = { GetTemplate = function() return template end }
            column:SetFixedConstraints(({150,170,0,24,140})[i], 0)
            if i == 3 then column:SetFillConstraints(1, 0) end
        end
    end
    function list:SetTableBuilderLayout(layout)
        self.setLayouts = (self.setLayouts or 0) + 1
        self.tableBuilderLayoutFunction = layout
        builder:Reset()
        layout(builder)
        builder:Arrange()
    end
    list.tableBuilder = builder
    list:SetTableBuilderLayout(nativeLayout)
    return builder, nativeLayout
end
return variants
