// Cheile funcțiilor pe plan. Trebuie să existe în tabelul public.features.
export const FEATURE_KEYS = [
  'bookings', 'seat_segments', 'dispatch', 'driver_app', 'tracking_link',
  'passenger_list', 'bookings_export', 'eta_traffic_notifications',
  'profit_dashboard', 'deviation_reports', 'sms_whatsapp', 'public_map',
  'parcels', 'vehicle_transport', 'gps_tracker_integration', 'in_app_navigation',
] as const;
export type FeatureKey = (typeof FEATURE_KEYS)[number];
