# Week 1 : Discovery Worked on Android but Not on iPhone

# Cross Platform Testing

## Error:

With an iPhone as the teacher, student phones found
nothing. There was no error message on either phone.

## Relevant Context

Each platform had passed its own checks: unit tests,
static analysis and a run on a single real phone. The
problem only showed once an iPhone acted as the teacher.

## Key Observation

The failure followed the teacher phone, not the student.
Android teachers were found; the iPhone teacher was not.
The session code lived in manufacturer data, a field iOS
does not let apps advertise.

## Solution

Reported the finding to the team. The code now
travels in the device name on iPhones (`CL` plus the
digits) and the scanner reads both places. Later the
token moved to a Bluetooth read, which works on both.

**Because**

iOS limits what an app may advertise to a name and service
UUIDs, and drops the rest without any error. Only a test
across both platforms could catch it.
