# Week 3 : Back Button Silently Stopped Attendance

# Guarding the Live Session Screen

## Error:

A teacher who pressed Back during class would leave the
session screen, which stops the Bluetooth broadcast.
Students could no longer check in, and nothing warned the
teacher.

## Relevant Context

The teacher phone only shares the token while the session
screen is open; leaving it disposes the broadcaster.

## Key Observation

Leaving the screen is a big action that looked like a
small one. It needed a confirmation step.

## Solution

Wrap the screen in `PopScope` and ask first:

``` dart
PopScope(
  canPop: false,
  onPopInvokedWithResult: (didPop, _) async {
    if (didPop) return;
    final navigator = Navigator.of(context);
    if (await _confirmLeave()) navigator.pop();
  },
  child: ...,
)
```

The dialog offers **Keep running** or **End session**; ending
also closes the session on the server.

**Because**

`canPop: false` stops the system back gesture, so the
screen decides what Back means while a class is live.
