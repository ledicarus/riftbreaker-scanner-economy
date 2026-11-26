-- Scanner Economy v1.0 by Led Icarus: Orbital Scanner override.
-- Holding Space at the scanner opens the scanner as usual plus the economy panel.

local building = require("lua/buildings/building.lua")
local SE = require("lua/scanner_economy/economy.lua")

class 'planet_scanner' ( building )
SE.Mixin(planet_scanner)

function planet_scanner:__init()
    building.__init(self,self)
end

function planet_scanner:OnInit()
    self.planetScannerVersion = 1
    self:RegisterHandler( self.entity, "InteractWithEntityRequest", "OnInteractWithEntityRequest" )
    self:SE_Setup()
end

function planet_scanner:OnLoad()
    building.OnLoad(self)
    if ( self.planetScannerVersion == nil or self.planetScannerVersion < 1 ) then
        self:RegisterHandler( self.entity, "InteractWithEntityRequest", "OnInteractWithEntityRequest" )
        self.planetScannerVersion = 1
    end
    self:SE_Setup()
end

function planet_scanner:OnInteractWithEntityRequest( event )
    local player = PlayerService:GetPlayerByMech( event:GetOwner() )
    QueueEvent("OpenPlanetaryScannerRequest", event:GetOwner(), player )
    self:SE_SafeOpenPanel()
end

return planet_scanner
