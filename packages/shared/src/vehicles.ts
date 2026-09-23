// Condițiile microbuzului: listă fixă, ca toți clienții să le poată compara.
// Trebuie să fie identică cu verificarea vehicles.features din migrația 2300.
export const VEHICLE_FEATURES = [
  'AC', 'WIFI', 'USB', 'TOILET', 'RECLINING_SEATS', 'TRAILER', 'PETS_ALLOWED', 'WHEELCHAIR', 'CHILD_SEAT',
] as const;
export type VehicleFeature = (typeof VEHICLE_FEATURES)[number];

export const VEHICLE_PHOTO_KINDS = ['EXTERIOR', 'INTERIOR', 'LUGGAGE', 'OTHER'] as const;
export type VehiclePhotoKind = (typeof VEHICLE_PHOTO_KINDS)[number];

export const FEATURE_LABELS: Record<'ro' | 'de', Record<VehicleFeature, string>> = {
  ro: {
    AC: 'Aer condiționat', WIFI: 'Wi-Fi', USB: 'Prize USB', TOILET: 'Toaletă', RECLINING_SEATS: 'Scaune rabatabile',
    TRAILER: 'Remorcă pentru bagaje', PETS_ALLOWED: 'Animale permise', WHEELCHAIR: 'Acces scaun cu rotile', CHILD_SEAT: 'Scaun pentru copii',
  },
  de: {
    AC: 'Klimaanlage', WIFI: 'WLAN', USB: 'USB-Anschlüsse', TOILET: 'Toilette', RECLINING_SEATS: 'Verstellbare Sitze',
    TRAILER: 'Gepäckanhänger', PETS_ALLOWED: 'Haustiere erlaubt', WHEELCHAIR: 'Rollstuhlgerecht', CHILD_SEAT: 'Kindersitz',
  },
};
