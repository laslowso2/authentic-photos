-- Authentic Photos - sample data for the demo.
-- Idempotent-ish: uses fixed ids with INSERT IGNORE so re-running won't duplicate.
USE authphotos;

INSERT IGNORE INTO photos (id, title, photographer, description, price_cents, currency, license_type, image_url) VALUES
  (1, 'Dawn Over the Fjord',      'Ingrid Solberg',  'First light spilling across a Norwegian fjord.',        4900, 'USD', 'standard', 'https://picsum.photos/seed/fjord/1200/800'),
  (2, 'Market Spices, Marrakech', 'Youssef El Amrani','Pyramids of saffron and paprika in the medina.',       3900, 'USD', 'standard', 'https://picsum.photos/seed/spices/1200/800'),
  (3, 'Neon Rain, Tokyo',         'Kenji Nakamura',  'Shinjuku backstreets reflected in wet asphalt.',        6900, 'USD', 'extended', 'https://picsum.photos/seed/neon/1200/800'),
  (4, 'Salt Flats Mirror',        'Camila Rojas',    'Bolivia''s Salar de Uyuni after the rains.',            5900, 'USD', 'extended', 'https://picsum.photos/seed/saltflat/1200/800'),
  (5, 'Highland Cattle',          'Fiona MacLeod',   'A shaggy Highland cow in Scottish mist.',               2900, 'USD', 'standard', 'https://picsum.photos/seed/cattle/1200/800'),
  (6, 'Desert Dunes at Dusk',     'Omar Haddad',     'Wind-carved ridges in the Empty Quarter.',              4400, 'USD', 'standard', 'https://picsum.photos/seed/dunes/1200/800');

-- A demo customer (as if they had already logged in via Thunder once).
INSERT IGNORE INTO customers (id, external_subject, email, display_name) VALUES
  (1, 'demo-subject-0001', 'demo.buyer@example.com', 'Demo Buyer');
