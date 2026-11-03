# Week 4 : One Student Marked Twice

# Atomic Claim Acceptance

## Error:

When a phone retried a claim after a slow network reply,
the server could accept the same one time code twice, or
record two rows for the same student.

## Relevant Context

Accepting a claim does two writes: mark the challenge as
used, then insert the attendance row. Done as two
separate steps, two requests arriving together could both
pass the "not used yet" check.

## Key Observation

The check and the write must happen as one step inside
the database, not in Python.

## Solution

Do both writes in one transaction and let the database
decide:

``` sql
update challenges set used_at = %s
 where id = %s and used_at is null
 returning id;

insert into attendance (...)
values (...)
on conflict (session_id, student_id) do nothing
returning *;
```

If the update returns nothing, another request already
used the code; if the insert returns nothing, the student
is already present. A genuine retry gets the stored record
back with `duplicate_retry: true`.

**Because**

`used_at is null` in the `where` clause makes the update
claim the row atomically: only one request can flip it.
The unique key on `(session_id, student_id)` does the
same for attendance.
