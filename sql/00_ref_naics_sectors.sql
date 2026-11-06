-- =====================================================================
-- 00_ref_naics_sectors.sql
-- Reference table: NAICS 2-digit sector code -> sector name.
-- Source: U.S. Census Bureau, 2022 NAICS sector definitions.
-- Manufacturing (31-33), Retail (44-45), Transportation (48-49) span
-- several 2-digit codes, so each code gets its own row.
--
-- is_tech_sector: our definition of "tech" used for "outside tech"
-- findings (see DECISIONS.md). Applied at a finer level in 03_clean.sql:
--   51    Information (software publishers, internet, telecom, data processing)
--   5415  Computer Systems Design & Related Services (IT services / consulting)
--   334   Computer & Electronic Product Manufacturing (hardware, chips)
-- =====================================================================
CREATE OR REPLACE TABLE ref_naics_sector AS
SELECT * FROM (VALUES
    ('11', 'Agriculture, Forestry, Fishing & Hunting'),
    ('21', 'Mining, Quarrying, Oil & Gas'),
    ('22', 'Utilities'),
    ('23', 'Construction'),
    ('31', 'Manufacturing'),
    ('32', 'Manufacturing'),
    ('33', 'Manufacturing'),
    ('42', 'Wholesale Trade'),
    ('44', 'Retail Trade'),
    ('45', 'Retail Trade'),
    ('48', 'Transportation & Warehousing'),
    ('49', 'Transportation & Warehousing'),
    ('51', 'Information'),
    ('52', 'Finance & Insurance'),
    ('53', 'Real Estate & Rental'),
    ('54', 'Professional, Scientific & Technical Services'),
    ('55', 'Management of Companies'),
    ('56', 'Administrative & Support Services'),
    ('61', 'Educational Services'),
    ('62', 'Health Care & Social Assistance'),
    ('71', 'Arts, Entertainment & Recreation'),
    ('72', 'Accommodation & Food Services'),
    ('81', 'Other Services'),
    ('92', 'Public Administration')
) AS t(naics2, sector_name);
