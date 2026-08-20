-- Production tower topology.
-- Keep this file free of test coordinates. Add server-owned tower definitions here.
-- Verified coordinates imported from the /telecom_tower_export capture batch.
-- Review physical placement and backhaul before treating this as final topology.
Config.Towers = {
{
id = 'BC-CHUMASH-01',
class = 'TOWN_MACRO',
coverageZone = 'TOWN',
purpose = 'Chumash coastal town coverage',
coords = vector3(-3132.92, 1097.85, 21.51),
coverage = {
radius = 1200.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 80.00,
},
-- capturedHeading = 283.46; validate before using as sector azimuth
},
{
id = 'BC-GRAPESEED-01',
class = 'TOWN_MACRO',
coverageZone = 'TOWN',
purpose = 'Grapeseed town coverage',
coords = vector3(1689.93, 4817.64, 45.96),
coverage = {
radius = 1200.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 80.00,
},
-- capturedHeading = 206.93; validate before using as sector azimuth
},
{
id = 'BC-HARMONY-01',
class = 'TOWN_MACRO',
coverageZone = 'TOWN',
purpose = 'Harmony town coverage',
coords = vector3(1181.93, 2644.72, 43.50),
coverage = {
radius = 1200.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 80.00,
},
-- capturedHeading = 34.02; validate before using as sector azimuth
},
{
id = 'BC-PALETO-01',
class = 'TOWN_MACRO',
coverageZone = 'TOWN',
purpose = 'Paleto Bay west town coverage',
coords = vector3(-751.19, 5560.72, 40.97),
coverage = {
radius = 1200.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 80.00,
},
-- capturedHeading = 223.94; validate before using as sector azimuth
},
{
id = 'BC-PALETO-02',
class = 'TOWN_MACRO',
coverageZone = 'TOWN',
purpose = 'Paleto Bay east town coverage',
coords = vector3(-67.12, 6421.71, 35.82),
coverage = {
radius = 1200.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 80.00,
},
-- capturedHeading = 124.72; validate before using as sector azimuth
},
{
id = 'BC-SANDY-01',
class = 'TOWN_MACRO',
coverageZone = 'TOWN',
purpose = 'Sandy Shores west town coverage',
coords = vector3(1856.94, 3691.29, 38.87),
coverage = {
radius = 1200.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 80.00,
},
-- capturedHeading = 212.60; validate before using as sector azimuth
},
{
id = 'BC-SANDY-02',
class = 'TOWN_MACRO',
coverageZone = 'TOWN',
purpose = 'Sandy Shores east town coverage',
coords = vector3(-201.60, 3659.33, 51.74),
coverage = {
radius = 1200.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 80.00,
},
-- capturedHeading = 153.07; validate before using as sector azimuth
},
{
id = 'BC-ZANCUDO-01',
class = 'TOWN_MACRO',
coverageZone = 'TOWN',
purpose = 'Fort Zancudo access settlement coverage',
coords = vector3(-2436.33, 2942.19, 41.82),
coverage = {
radius = 1200.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 80.00,
},
-- capturedHeading = 266.46; validate before using as sector azimuth
},
{
id = 'HW-GOH-01',
class = 'HIGHWAY_REPEATER',
coverageZone = 'HIGHWAY',
purpose = 'Great Ocean Highway south repeater',
coords = vector3(-2184.18, 4295.78, 53.81),
coverage = {
radius = 750.00,
minimum = 50.00,
},
technologies = { '4G' },
capacity = {
maximum = 30.00,
},
-- capturedHeading = 48.19; validate before using as sector azimuth
},
{
id = 'HW-GOH-02',
class = 'HIGHWAY_REPEATER',
coverageZone = 'HIGHWAY',
purpose = 'Great Ocean Highway north repeater',
coords = vector3(-1488.54, 4981.62, 67.33),
coverage = {
radius = 750.00,
minimum = 50.00,
},
technologies = { '4G' },
capacity = {
maximum = 30.00,
},
-- capturedHeading = 102.05; validate before using as sector azimuth
},
{
id = 'HW-NORTH-01',
class = 'HIGHWAY_REPEATER',
coverageZone = 'HIGHWAY',
purpose = 'Northern highway transition repeater',
coords = vector3(1025.25, 6503.25, 20.97),
coverage = {
radius = 750.00,
minimum = 50.00,
},
technologies = { '4G' },
capacity = {
maximum = 30.00,
},
-- capturedHeading = 201.26; validate before using as sector azimuth
},
{
id = 'HW-PALOMINO-01',
class = 'HIGHWAY_REPEATER',
coverageZone = 'HIGHWAY',
purpose = 'Palomino Freeway east repeater',
coords = vector3(2590.98, 430.23, 111.89),
coverage = {
radius = 750.00,
minimum = 50.00,
},
technologies = { '4G' },
capacity = {
maximum = 30.00,
},
-- capturedHeading = 0.00; validate before using as sector azimuth
},
{
id = 'HW-R68-01',
class = 'HIGHWAY_REPEATER',
coverageZone = 'HIGHWAY',
purpose = 'Route 68 highway repeater',
coords = vector3(1573.41, 1247.13, 97.15),
coverage = {
radius = 750.00,
minimum = 50.00,
},
technologies = { '4G' },
capacity = {
maximum = 30.00,
},
-- capturedHeading = 317.48; validate before using as sector azimuth
},
{
id = 'HW-SENORA-01',
class = 'HIGHWAY_REPEATER',
coverageZone = 'HIGHWAY',
purpose = 'Senora Freeway south repeater',
coords = vector3(1968.45, 4628.43, 46.43),
coverage = {
radius = 750.00,
minimum = 50.00,
},
technologies = { '4G' },
capacity = {
maximum = 30.00,
},
-- capturedHeading = 25.51; validate before using as sector azimuth
},
{
id = 'HW-SENORA-02',
class = 'HIGHWAY_REPEATER',
coverageZone = 'HIGHWAY',
purpose = 'Senora Freeway north repeater',
coords = vector3(2430.66, 4961.09, 52.87),
coverage = {
radius = 750.00,
minimum = 50.00,
},
technologies = { '4G' },
capacity = {
maximum = 30.00,
},
-- capturedHeading = 144.57; validate before using as sector azimuth
},
{
id = 'HW-SANDY-EAST-01',
class = 'HIGHWAY_REPEATER',
coverageZone = 'HIGHWAY',
purpose = 'TP-07 verified Sandy eastern corridor highway gap coverage',
coords = vector3(2436.88, 2826.04, 49.53),
coverage = {
radius = 750.00,
minimum = 50.00,
},
technologies = { '4G' },
capacity = {
maximum = 30.00,
},
-- capturedHeading = 0.00; validate before using as sector azimuth
},
{
id = 'HW-SENORA-CORRIDOR-01',
class = 'HIGHWAY_REPEATER',
coverageZone = 'HIGHWAY',
purpose = 'TP-07 verified Sandy-to-Senora corridor highway gap coverage',
coords = vector3(2742.58, 4410.03, 48.29),
coverage = {
radius = 750.00,
minimum = 50.00,
},
technologies = { '4G' },
capacity = {
maximum = 30.00,
},
-- capturedHeading = 167.24; validate before using as sector azimuth
},
{
id = 'HW-DAVIS-FREEWAY-01',
class = 'HIGHWAY_REPEATER',
coverageZone = 'HIGHWAY',
purpose = 'TP-07 verified La Puerta-to-Davis freeway gap coverage',
coords = vector3(-305.85, -1272.62, 45.12),
coverage = {
radius = 750.00,
minimum = 50.00,
},
technologies = { '4G' },
capacity = {
maximum = 30.00,
},
-- capturedHeading = 0.00; validate before using as sector azimuth
},
{
id = 'LS-CYPRESS-01',
class = 'METRO_MACRO',
coverageZone = 'METRO_EDGE',
purpose = 'Cypress Flats industrial edge coverage',
coords = vector3(1068.69, -2175.07, 31.82),
coverage = {
radius = 850.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 150.00,
},
-- capturedHeading = 85.04; validate before using as sector azimuth
},
{
id = 'LS-DAVIS-01',
class = 'METRO_MACRO',
coverageZone = 'METRO_EDGE',
purpose = 'Davis urban edge coverage',
coords = vector3(390.87, -1683.19, 52.33),
coverage = {
radius = 850.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 150.00,
},
-- capturedHeading = 42.52; validate before using as sector azimuth
},
{
id = 'LS-DELPERRO-01',
class = 'METRO_MACRO',
coverageZone = 'METRO_EDGE',
purpose = 'Del Perro urban edge coverage',
coords = vector3(-1597.52, -871.03, 11.87),
coverage = {
radius = 850.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 150.00,
},
-- capturedHeading = 155.91; validate before using as sector azimuth
},
{
id = 'LS-DOWNTOWN-01',
class = 'METRO_MACRO',
coverageZone = 'METRO_CORE',
purpose = 'Downtown Los Santos metro core coverage',
coords = vector3(438.99, -634.52, 34.45),
coverage = {
radius = 850.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 150.00,
},
-- capturedHeading = 73.70; validate before using as sector azimuth
},
{
id = 'LS-EAST-01',
class = 'METRO_MACRO',
coverageZone = 'METRO_EDGE',
purpose = 'East Los Santos urban edge coverage',
coords = vector3(381.05, 247.36, 116.55),
coverage = {
radius = 850.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 150.00,
},
-- capturedHeading = 11.34; validate before using as sector azimuth
},
{
id = 'LS-LAMESA-01',
class = 'METRO_MACRO',
coverageZone = 'METRO_EDGE',
purpose = 'La Mesa urban edge coverage',
coords = vector3(816.95, -1576.01, 38.73),
coverage = {
radius = 850.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 150.00,
},
-- capturedHeading = 90.71; validate before using as sector azimuth
},
{
id = 'LS-LAPUERTA-01',
class = 'METRO_MACRO',
coverageZone = 'METRO_CORE',
purpose = 'La Puerta metro coverage',
coords = vector3(-1116.94, -1459.31, 8.22),
coverage = {
radius = 850.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 150.00,
},
-- capturedHeading = 311.81; validate before using as sector azimuth
},
{
id = 'LS-LSIA-01',
class = 'METRO_MACRO',
coverageZone = 'METRO_CORE',
purpose = 'Los Santos International Airport metro coverage',
coords = vector3(-981.56, -2637.11, 89.52),
coverage = {
radius = 850.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 150.00,
},
-- capturedHeading = 155.91; validate before using as sector azimuth
},
{
id = 'LS-MIRRORPARK-01',
class = 'METRO_MACRO',
coverageZone = 'METRO_EDGE',
purpose = 'Mirror Park urban edge coverage',
coords = vector3(1124.80, -499.25, 78.53),
coverage = {
radius = 850.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 150.00,
},
-- capturedHeading = 175.75; validate before using as sector azimuth
},
{
id = 'LS-MISSIONROW-01',
class = 'METRO_MACRO',
coverageZone = 'METRO_CORE',
purpose = 'Mission Row metro core coverage',
coords = vector3(480.32, -939.01, 36.34),
coverage = {
radius = 850.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 150.00,
},
-- capturedHeading = 178.58; validate before using as sector azimuth
},
{
id = 'LS-MURRIETA-01',
class = 'METRO_MACRO',
coverageZone = 'METRO_EDGE',
purpose = 'Murrieta Heights urban edge coverage',
coords = vector3(1198.77, -1279.46, 39.46),
coverage = {
radius = 850.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 150.00,
},
-- capturedHeading = 240.94; validate before using as sector azimuth
},
{
id = 'LS-PORT-01',
class = 'METRO_MACRO',
coverageZone = 'METRO_CORE',
purpose = 'Port of Los Santos industrial metro coverage',
coords = vector3(313.49, -2911.90, 6.11),
coverage = {
radius = 850.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 150.00,
},
-- capturedHeading = 85.04; validate before using as sector azimuth
},
{
id = 'LS-RICHMAN-01',
class = 'METRO_MACRO',
coverageZone = 'METRO_EDGE',
purpose = 'Richman urban edge coverage',
coords = vector3(-944.18, 314.97, 75.01),
coverage = {
radius = 850.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 150.00,
},
-- capturedHeading = 209.76; validate before using as sector azimuth
},
{
id = 'LS-ROCKFORD-01',
class = 'METRO_MACRO',
coverageZone = 'METRO_EDGE',
purpose = 'Rockford Hills urban edge coverage',
coords = vector3(-477.55, -87.28, 46.37),
coverage = {
radius = 850.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 150.00,
},
-- capturedHeading = 144.57; validate before using as sector azimuth
},
{
id = 'LS-VESPUCCI-01',
class = 'METRO_MACRO',
coverageZone = 'METRO_CORE',
purpose = 'Vespucci and beachfront metro coverage',
coords = vector3(-1184.18, -705.81, 42.27),
coverage = {
radius = 850.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 150.00,
},
-- capturedHeading = 223.94; validate before using as sector azimuth
},
{
id = 'LS-VINEWOOD-01',
class = 'METRO_MACRO',
coverageZone = 'METRO_EDGE',
purpose = 'Vinewood urban edge coverage',
coords = vector3(610.69, 142.91, 106.57),
coverage = {
radius = 850.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 150.00,
},
-- capturedHeading = 215.43; validate before using as sector azimuth
},
{
id = 'RM-CHILIAD-CABLE-01',
class = 'REMOTE_REPEATER',
coverageZone = 'WILDERNESS',
purpose = 'Mount Chiliad cable access remote repeater',
coords = vector3(452.53, 5565.34, 796.08),
coverage = {
radius = 450.00,
minimum = 50.00,
},
technologies = { '4G' },
capacity = {
maximum = 10.00,
},
-- capturedHeading = 102.05; validate before using as sector azimuth
},
{
id = 'CUSTOM-LARGE-01',
class = 'RURAL_MACRO',
coverageZone = 'WILDERNESS',
purpose = 'Additional large-area wilderness coverage',
coords = vector3(-562.31, 1897.28, 209.07),
coverage = {
radius = 1500.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 50.00,
},
},
{
id = 'CUSTOM-MEDIUM-01',
class = 'TOWN_MACRO',
coverageZone = 'RURAL',
purpose = 'Additional medium-area coverage site 1',
coords = vector3(-1978.43, 370.34, 92.76),
coverage = {
radius = 1200.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 80.00,
},
},
{
id = 'CUSTOM-MEDIUM-02',
class = 'TOWN_MACRO',
coverageZone = 'RURAL',
purpose = 'Additional medium-area coverage site 2',
coords = vector3(2475.05, 1492.62, 36.04),
coverage = {
radius = 1200.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 80.00,
},
},
{
id = 'CUSTOM-HIGHWAY-01',
class = 'HIGHWAY_REPEATER',
coverageZone = 'HIGHWAY',
purpose = 'Additional highway repeater coverage',
coords = vector3(2241.41, -528.77, 92.46),
coverage = {
radius = 750.00,
minimum = 50.00,
},
technologies = { '4G' },
capacity = {
maximum = 30.00,
},
},
{
id = 'CUSTOM-MEDIUM-03',
class = 'TOWN_MACRO',
coverageZone = 'TOWN',
purpose = 'Additional medium-area coverage site 3',
coords = vector3(1728.63, 6414.19, 41.07),
coverage = {
radius = 1200.00,
minimum = 50.00,
},
technologies = { '4G', '5G' },
capacity = {
maximum = 80.00,
},
},
}
