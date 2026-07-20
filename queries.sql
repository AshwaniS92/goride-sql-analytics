-- Q01. Active driver headcount.
SELECT COUNT(*) AS active_driver_count
FROM driver
WHERE left_date IS NULL;

-- Q02. Total platform GMV.
SELECT ROUND(SUM(amount), 2) AS total_gmv_eur
FROM payment
WHERE status = 'succeeded';

-- Q03. Total refund exposure.
SELECT ROUND(SUM(amount), 2) AS total_refunded_eur
FROM payment
WHERE status = 'refunded';

-- Q04. Customer base split.
SELECT customer_type, COUNT(*) AS customer_count
FROM customer
GROUP BY customer_type
ORDER BY customer_type ASC
LIMIT 5;

-- Q05. Voucher pool size.
SELECT COUNT(DISTINCT rider_customer_id) AS voucher_eligible_customer_count
FROM trip
WHERE LOWER(TRIM(status)) IN ('cancelled_by_rider', 'cancelled_by_driver', 'aborted', 'no_show', 'noshow');

-- Q06. Busiest pickup zones.
SELECT TRIM(z.zone_name) AS zone_name, COUNT(*) AS trip_count
FROM trip t
JOIN zone z ON z.zone_id = t.pickup_zone_id
GROUP BY TRIM(z.zone_name)
ORDER BY trip_count DESC, zone_name ASC
LIMIT 10;

-- Q07. Average ride fare by source.
SELECT t.source_system, ROUND(AVG(p.amount), 2) AS avg_ride_fare_eur
FROM payment p
JOIN trip t ON p.service_type = 'ride' AND p.service_id = t.trip_id::text
WHERE p.status = 'succeeded'
GROUP BY t.source_system
ORDER BY avg_ride_fare_eur DESC, t.source_system ASC
LIMIT 5;

-- Q08. Payment success rate by service.
SELECT
  CASE WHEN payment_correction_flag THEN 'package' ELSE service_type END AS service_type_corrected,
  COUNT(*) AS total_attempts,
  COUNT(*) FILTER (WHERE status = 'succeeded') AS successful_attempts,
  ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'succeeded') / COUNT(*), 2) AS success_rate_percent
FROM payment
GROUP BY service_type_corrected
ORDER BY success_rate_percent DESC, service_type_corrected ASC
LIMIT 5;

-- Q09. Trip outcome breakdown.
SELECT
  CASE
    WHEN LOWER(TRIM(status)) = 'finished' THEN 'completed'
    WHEN LOWER(TRIM(status)) = 'aborted' THEN 'cancelled_by_rider'
    WHEN LOWER(TRIM(status)) = 'noshow' THEN 'no_show'
    ELSE LOWER(TRIM(status))
  END AS status_normalized,
  COUNT(*) AS trip_count
FROM trip
GROUP BY status_normalized
ORDER BY status_normalized ASC
LIMIT 10;

-- Q10. Premium fare zones.
SELECT
  REGEXP_REPLACE(REPLACE(TRIM(z.zone_name), '-', ' '), '\\s+', ' ', 'g') AS zone_name_canonical,
  COUNT(DISTINCT t.trip_id) AS completed_ride_count,
  ROUND(AVG(p.amount), 2) AS avg_fare_eur
FROM trip t
JOIN zone z ON z.zone_id = t.pickup_zone_id
JOIN payment p ON p.service_type = 'ride' AND p.service_id = t.trip_id::text AND p.status = 'succeeded'
WHERE CASE
    WHEN LOWER(TRIM(t.status)) = 'finished' THEN 'completed'
    WHEN LOWER(TRIM(t.status)) = 'aborted' THEN 'cancelled_by_rider'
    WHEN LOWER(TRIM(t.status)) = 'noshow' THEN 'no_show'
    ELSE LOWER(TRIM(t.status))
  END = 'completed'
GROUP BY zone_name_canonical
ORDER BY avg_fare_eur DESC, zone_name_canonical ASC
LIMIT 10;

-- Q11. Top-rated drivers leaderboard.
SELECT
  d.driver_id,
  d.driver_name,
  ROUND(AVG(CASE WHEN r.source_system = 'quickhop' THEN r.score / 2.0 ELSE r.score END), 2) AS avg_normalized_rating,
  COUNT(*) AS rated_ride_count
FROM rating r
JOIN trip t ON r.service_type = 'ride' AND r.service_id = t.trip_id::text
JOIN driver d ON d.driver_id = t.driver_id
GROUP BY d.driver_id, d.driver_name
HAVING COUNT(*) >= 30
ORDER BY avg_normalized_rating DESC, d.driver_id ASC
LIMIT 20;

-- Q12. Pending merge queue.
WITH norm AS (
  SELECT
    customer_id, source_system, email, phone, merged_into_customer_id,
    REGEXP_REPLACE(COALESCE(phone, ''), '[^0-9]', '', 'g') AS digits_only
  FROM customer
),
phone_norm AS (
  SELECT
    customer_id, source_system, email, phone, merged_into_customer_id,
    CASE WHEN digits_only LIKE '490%' THEN '49' || SUBSTRING(digits_only FROM 4)
         ELSE digits_only
    END AS phone_normalized
  FROM norm
  WHERE digits_only <> ''
),
g AS (SELECT * FROM phone_norm WHERE source_system = 'goride'   AND merged_into_customer_id IS NULL),
q AS (SELECT * FROM phone_norm WHERE source_system = 'quickhop' AND merged_into_customer_id IS NULL)
SELECT
  g.customer_id AS goride_customer_id,
  q.customer_id AS quickhop_customer_id,
  g.phone_normalized,
  g.email
FROM g
JOIN q ON g.phone_normalized = q.phone_normalized
ORDER BY g.email ASC, g.customer_id ASC
LIMIT 200;

-- Q13. Parcel-heavy zones for ride cross-sell.
WITH rides AS (
  SELECT REGEXP_REPLACE(REPLACE(TRIM(z.zone_name), '-', ' '), '\\s+', ' ', 'g') AS zone_name_canonical, COUNT(*) AS ride_count
  FROM trip t JOIN zone z ON z.zone_id = t.pickup_zone_id
  GROUP BY 1
), parcels AS (
  SELECT REGEXP_REPLACE(REPLACE(TRIM(z.zone_name), '-', ' '), '\\s+', ' ', 'g') AS zone_name_canonical, COUNT(*) AS parcel_count
  FROM package_delivery pd JOIN zone z ON z.zone_id = pd.pickup_zone_id
  GROUP BY 1
)
SELECT
  COALESCE(r.zone_name_canonical, p.zone_name_canonical) AS zone_name_canonical,
  COALESCE(r.ride_count, 0) AS ride_count,
  COALESCE(p.parcel_count, 0) AS parcel_count,
  ROUND(100.0 * COALESCE(p.parcel_count, 0) / NULLIF(COALESCE(r.ride_count, 0) + COALESCE(p.parcel_count, 0), 0), 2) AS parcel_share_percent
FROM rides r
FULL OUTER JOIN parcels p ON p.zone_name_canonical = r.zone_name_canonical
WHERE 100.0 * COALESCE(p.parcel_count, 0) / NULLIF(COALESCE(r.ride_count, 0) + COALESCE(p.parcel_count, 0), 0) > 18
ORDER BY parcel_share_percent DESC, zone_name_canonical ASC
LIMIT 25;

-- Q14. Advertising target zones.
WITH zone_trips AS (
  SELECT
    REGEXP_REPLACE(REPLACE(TRIM(z.zone_name), '-', ' '), '\\s+', ' ', 'g') AS zone_name_canonical,
    t.trip_id,
    CASE
      WHEN LOWER(TRIM(t.status)) = 'finished' THEN 'completed'
      WHEN LOWER(TRIM(t.status)) = 'aborted' THEN 'cancelled_by_rider'
      WHEN LOWER(TRIM(t.status)) = 'noshow' THEN 'no_show'
      ELSE LOWER(TRIM(t.status))
    END AS status_normalized
  FROM trip t JOIN zone z ON z.zone_id = t.pickup_zone_id
)
SELECT
  zone_name_canonical,
  COUNT(*) AS total_rides,
  COUNT(*) FILTER (WHERE status_normalized IN ('cancelled_by_rider', 'cancelled_by_driver', 'no_show')) AS cancelled_rides,
  ROUND(100.0 * COUNT(*) FILTER (WHERE status_normalized IN ('cancelled_by_rider', 'cancelled_by_driver', 'no_show')) / COUNT(*), 2) AS cancellation_rate_percent
FROM zone_trips
GROUP BY zone_name_canonical
HAVING ROUND(100.0 * COUNT(*) FILTER (WHERE status_normalized IN ('cancelled_by_rider', 'cancelled_by_driver', 'no_show')) / COUNT(*), 2) > 25
   AND COUNT(*) < 1100
ORDER BY cancellation_rate_percent DESC, zone_name_canonical ASC
LIMIT 25;

-- Q15. Top revenue vehicles.
WITH service_vehicle AS (
  SELECT t.trip_id::text AS service_id, 'ride' AS service_type_corrected, v.vehicle_id, v.license_plate
  FROM trip t JOIN vehicle v ON v.vehicle_id = t.vehicle_id
  UNION ALL
  SELECT pd.delivery_id::text, 'package', v.vehicle_id, v.license_plate
  FROM package_delivery pd JOIN vehicle v ON v.vehicle_id = pd.vehicle_id
)
SELECT sv.vehicle_id, sv.license_plate, ROUND(SUM(p.amount), 2) AS total_revenue_eur
FROM payment p
JOIN service_vehicle sv
  ON sv.service_id = p.service_id
 AND sv.service_type_corrected = CASE WHEN p.payment_correction_flag THEN 'package' ELSE p.service_type END
WHERE p.status = 'succeeded'
GROUP BY sv.vehicle_id, sv.license_plate
ORDER BY total_revenue_eur DESC, sv.vehicle_id ASC
LIMIT 5;

-- Q16. Revenue mix for the board.
WITH service_payer AS (
  SELECT t.trip_id::text AS service_id, 'ride' AS service_type_corrected, t.source_system, c.customer_type
  FROM trip t JOIN customer c ON c.customer_id = t.rider_customer_id
  UNION ALL
  SELECT pd.delivery_id::text, 'package', pd.source_system, c.customer_type
  FROM package_delivery pd JOIN customer c ON c.customer_id = pd.sender_customer_id
)
SELECT sp.source_system, sp.service_type_corrected, sp.customer_type, ROUND(SUM(p.amount), 2) AS total_revenue_eur
FROM payment p
JOIN service_payer sp
  ON sp.service_id = p.service_id
 AND sp.service_type_corrected = CASE WHEN p.payment_correction_flag THEN 'package' ELSE p.service_type END
WHERE p.status = 'succeeded'
GROUP BY sp.source_system, sp.service_type_corrected, sp.customer_type
ORDER BY total_revenue_eur DESC, sp.source_system ASC, sp.service_type_corrected ASC, sp.customer_type ASC
LIMIT 25;


-- Q17. Payment service-type reconciliation errors.
SELECT
  p.payment_id,
  p.service_type AS claimed_service_type,
  CASE WHEN p.service_type = 'ride' THEN 'package' ELSE 'ride' END AS actual_service_type,
  p.service_id
FROM payment p
WHERE (p.service_type = 'ride' AND EXISTS (SELECT 1 FROM package_delivery pd WHERE pd.delivery_id::text = p.service_id) AND NOT EXISTS (SELECT 1 FROM trip t WHERE t.trip_id::text = p.service_id))
   OR (p.service_type = 'package' AND EXISTS (SELECT 1 FROM trip t WHERE t.trip_id::text = p.service_id) AND NOT EXISTS (SELECT 1 FROM package_delivery pd WHERE pd.delivery_id::text = p.service_id))
ORDER BY p.payment_id ASC
LIMIT 100;

-- Q18. Lapsed customers for win-back.
WITH completed AS (
  SELECT COALESCE(c.merged_into_customer_id, c.customer_id) AS master_customer_id,
         c.email,
         t.completed_at::date AS ride_date
  FROM trip t
  JOIN customer c ON c.customer_id = t.rider_customer_id
  WHERE c.customer_type = 'individual'
    AND CASE
      WHEN LOWER(TRIM(t.status)) = 'finished' THEN 'completed'
      WHEN LOWER(TRIM(t.status)) = 'aborted' THEN 'cancelled_by_rider'
      WHEN LOWER(TRIM(t.status)) = 'noshow' THEN 'no_show'
      ELSE LOWER(TRIM(t.status))
    END = 'completed'
), latest AS (
  SELECT MAX(ride_date) AS max_ride_date FROM completed
), agg AS (
  SELECT master_customer_id, MIN(email) AS email, COUNT(*) AS total_completed_rides, MAX(ride_date) AS last_ride_date
  FROM completed
  GROUP BY master_customer_id
)
SELECT master_customer_id, email, total_completed_rides, last_ride_date,
       ((SELECT max_ride_date FROM latest) - last_ride_date) AS days_since_last_ride
FROM agg
WHERE total_completed_rides >= 3
  AND ((SELECT max_ride_date FROM latest) - last_ride_date) >= 60
ORDER BY days_since_last_ride DESC, master_customer_id ASC
LIMIT 100;

-- Q19. Berlin zones by average monthly rider spending.
SELECT
  REGEXP_REPLACE(REPLACE(TRIM(z.zone_name), '-', ' '), '\\s+', ' ', 'g') AS zone_name_canonical,
  COUNT(DISTINCT (t.rider_customer_id, DATE_TRUNC('month', t.requested_at))) AS distinct_rider_months,
  ROUND(SUM(p.amount), 2) AS total_zone_spend_eur,
  ROUND(SUM(p.amount) / COUNT(DISTINCT (t.rider_customer_id, DATE_TRUNC('month', t.requested_at))), 2) AS avg_spending_per_rider_per_month_eur
FROM trip t
JOIN zone z ON z.zone_id = t.pickup_zone_id
JOIN payment p ON p.service_id = t.trip_id::text
 AND CASE WHEN p.payment_correction_flag THEN 'package' ELSE p.service_type END = 'ride'
WHERE p.status = 'succeeded'
GROUP BY zone_name_canonical
ORDER BY avg_spending_per_rider_per_month_eur DESC, zone_name_canonical ASC
LIMIT 25;

-- Q20. Top earners by average monthly revenue.
WITH activity AS (
  SELECT COALESCE(d.merged_into_driver_id, d.driver_id) AS master_driver_id,
         DATE_TRUNC('month', t.requested_at) AS active_month,
         p.amount
  FROM trip t
  JOIN driver d ON d.driver_id = t.driver_id
  JOIN payment p ON p.service_id = t.trip_id::text
   AND CASE WHEN p.payment_correction_flag THEN 'package' ELSE p.service_type END = 'ride'
  WHERE p.status = 'succeeded'
    AND CASE WHEN LOWER(TRIM(t.status)) = 'finished' THEN 'completed' ELSE LOWER(TRIM(t.status)) END = 'completed'
  UNION ALL
  SELECT COALESCE(d.merged_into_driver_id, d.driver_id),
         DATE_TRUNC('month', pd.requested_at),
         p.amount
  FROM package_delivery pd
  JOIN driver d ON d.driver_id = pd.driver_id
  JOIN payment p ON p.service_id = pd.delivery_id::text
   AND CASE WHEN p.payment_correction_flag THEN 'package' ELSE p.service_type END = 'package'
  WHERE p.status = 'succeeded'
    AND LOWER(TRIM(pd.status)) = 'delivered'
)
SELECT a.master_driver_id, md.driver_name,
       COUNT(DISTINCT active_month) AS active_months,
       ROUND(SUM(amount), 2) AS total_revenue_eur,
       ROUND(SUM(amount) / COUNT(DISTINCT active_month), 2) AS avg_monthly_revenue_eur
FROM activity a
JOIN driver md ON md.driver_id = a.master_driver_id
GROUP BY a.master_driver_id, md.driver_name
ORDER BY avg_monthly_revenue_eur DESC, a.master_driver_id ASC
LIMIT 20;

-- Q21. Refund-impact on revenue.
WITH service_source AS (
  SELECT trip_id::text AS service_id, 'ride' AS service_type_corrected, source_system FROM trip
  UNION ALL
  SELECT delivery_id::text, 'package', source_system FROM package_delivery
)
SELECT
  s.source_system,
  s.service_type_corrected,
  ROUND(SUM(CASE WHEN p.status = 'succeeded' THEN p.amount ELSE 0 END), 2) AS collected_revenue_eur,
  ROUND(SUM(CASE WHEN p.status = 'refunded' THEN p.amount ELSE 0 END), 2) AS refunded_revenue_eur,
  ROUND(SUM(CASE WHEN p.status = 'succeeded' THEN p.amount ELSE 0 END) - SUM(CASE WHEN p.status = 'refunded' THEN p.amount ELSE 0 END), 2) AS net_revenue_eur
FROM payment p
JOIN service_source s
  ON s.service_id = p.service_id
 AND s.service_type_corrected = CASE WHEN p.payment_correction_flag THEN 'package' ELSE p.service_type END
GROUP BY s.source_system, s.service_type_corrected
ORDER BY net_revenue_eur DESC, s.source_system ASC, s.service_type_corrected ASC
LIMIT 25;

-- Q22. Top businesses by average monthly spend.
SELECT
  c.customer_id,
  c.business_name,
  COUNT(DISTINCT DATE_TRUNC('month', pd.requested_at)) AS active_months,
  ROUND(SUM(p.amount), 2) AS total_spend_eur,
  ROUND(SUM(p.amount) / COUNT(DISTINCT DATE_TRUNC('month', pd.requested_at)), 2) AS avg_monthly_spend_eur
FROM customer c
JOIN package_delivery pd ON pd.sender_customer_id = c.customer_id
JOIN payment p ON p.service_id = pd.delivery_id::text
 AND CASE WHEN p.payment_correction_flag THEN 'package' ELSE p.service_type END = 'package'
WHERE c.customer_type = 'business'
  AND p.status = 'succeeded'
GROUP BY c.customer_id, c.business_name
ORDER BY avg_monthly_spend_eur DESC, c.customer_id ASC
LIMIT 20;

-- Q23. Fraud detection: cancelled trips with kept payments.
SELECT
  t.trip_id,
  t.source_system,
  t.status AS trip_status,
  p.payment_id,
  ROUND(p.amount, 2) AS payment_amount_eur
FROM trip t
JOIN payment p ON p.service_id = t.trip_id::text
 AND CASE WHEN p.payment_correction_flag THEN 'package' ELSE p.service_type END = 'ride'
 AND p.status = 'succeeded'
WHERE LOWER(TRIM(t.status)) IN ('cancelled_by_rider', 'cancelled_by_driver', 'aborted', 'no_show', 'noshow')
  AND NOT EXISTS (
    SELECT 1
    FROM payment pr
    WHERE pr.service_id = p.service_id
      AND CASE WHEN pr.payment_correction_flag THEN 'package' ELSE pr.service_type END = 'ride'
      AND pr.status = 'refunded'
  )
ORDER BY payment_amount_eur DESC, t.trip_id ASC
LIMIT 50;

-- Q24. Ghost trips audit.
SELECT
  t.trip_id,
  t.source_system,
  t.driver_id,
  t.vehicle_id,
  t.requested_at::date AS trip_date
FROM trip t
WHERE LOWER(TRIM(t.status)) IN ('completed', 'finished')
  AND NOT EXISTS (
    SELECT 1
    FROM driver_vehicle_assignment dva
    WHERE dva.driver_id = t.driver_id
      AND dva.vehicle_id = t.vehicle_id
      AND t.requested_at::date >= dva.valid_from
      AND (dva.valid_to IS NULL OR t.requested_at::date <= dva.valid_to)
  )
ORDER BY trip_date DESC, t.trip_id ASC
LIMIT 50;

-- Q25. Berlin zones by average monthly driver earnings.
SELECT
  REGEXP_REPLACE(REPLACE(TRIM(z.zone_name), '-', ' '), '\\s+', ' ', 'g') AS zone_name_canonical,
  COUNT(DISTINCT (COALESCE(d.merged_into_driver_id, d.driver_id), DATE_TRUNC('month', t.requested_at))) AS qualifying_driver_months,
  ROUND(SUM(p.amount), 2) AS total_zone_revenue_eur,
  ROUND(SUM(p.amount) / COUNT(DISTINCT (COALESCE(d.merged_into_driver_id, d.driver_id), DATE_TRUNC('month', t.requested_at))), 2) AS avg_revenue_per_driver_per_month_eur
FROM trip t
JOIN driver d ON d.driver_id = t.driver_id
JOIN zone z ON z.zone_id = t.pickup_zone_id
JOIN payment p ON p.service_id = t.trip_id::text
 AND CASE WHEN p.payment_correction_flag THEN 'package' ELSE p.service_type END = 'ride'
WHERE p.status = 'succeeded'
  AND CASE WHEN LOWER(TRIM(t.status)) = 'finished' THEN 'completed' ELSE LOWER(TRIM(t.status)) END = 'completed'
GROUP BY zone_name_canonical
ORDER BY avg_revenue_per_driver_per_month_eur DESC, zone_name_canonical ASC
LIMIT 25;
