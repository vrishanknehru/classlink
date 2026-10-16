# Evaluation Data

This folder holds the raw measurements for the evaluation in the SRS
(Appendix D). Rules:

1. **Real runs only.** Every row comes from an executed test on real phones in
   a real room. Never pre-fill or estimate.
2. **Raw before summary.** Commit the raw CSV first. Compute tables and figures
   from it afterwards, and name the CSV a figure came from.
3. **One file per session of testing.** Name files `YYYY-MM-DD-room-label.csv`.

Start from [`TEMPLATE.csv`](TEMPLATE.csv), which has the header row and no data.

## Procedure for one scenario

1. The teacher phone starts a session. Note the teacher phone model.
2. A student phone goes to a labelled position (front, middle, back, door,
   corridor, adjacent_room) and checks in.
3. Record `expected` (accept inside the room under the policy, reject outside),
   the claim values, the result from the server, and the latencies.
4. Repeat for each position with at least two student phone models.

The server also records every accepted and rejected claim in `audit_events`,
which you can cross check against the CSV.

## Columns

| Column | Meaning |
|---|---|
| run_id | Identifier for one scenario run |
| timestamp_utc | ISO 8601 time of the attempt |
| teacher_phone, student_phone | Device models |
| android_version | Version on the student phone |
| room_label | Room name |
| position_label | front, middle, back, door, corridor, adjacent_room |
| expected | accept or reject |
| median_rssi_dbm, sample_count | Values sent in the claim |
| result | accepted, or the rejection reason |
| discovery_ms, completion_ms | Latencies in milliseconds |
