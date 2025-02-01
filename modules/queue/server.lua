Queue = {}
Queue.__index = Queue

function Queue.insert(self, player, position)
	if position then
		for i = #self, position, -1 do
			self[i + 1] = self[i]
		end
		self[position] = player
	else
		self[#self + 1] = player
	end
end

function Queue.connect(self)
    if #self > 0 then
        local first = self[1]
        for i = 1, #self - 1 do
            self[i] = self[i + 1]
        end
        self[#self] = nil
        return first
    end
    return nil
end

function Queue.remove(self, license)
	local position = self:getPosition(license)
	if position then
		for i = position, #self - 1 do
			self[i] = self[i + 1]
		end
		self[#self] = nil
	end
end

function Queue.getPosition(self, _player)
	for position, player in pairs(self) do
		if player == _player then
			return position
		end
	end
	return nil
end

function Queue.getSize(self)
	return #self
end

setmetatable(Queue, {
	__call = function()
		local queue = {}
		setmetatable(queue, Queue)
		return queue
	end
})
