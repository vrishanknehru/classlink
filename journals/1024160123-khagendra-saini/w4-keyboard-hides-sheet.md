# Week 4 : Keyboard Covered the Correction Form

# Bottom Sheet and the Keyboard

## Error:

When a teacher types the reason for a correction, the
keyboard would cover the text field and the **Save
correction** button.

## Relevant Context

The correction form opens in a bottom sheet:

``` dart
showModalBottomSheet<(bool, String)>(
  context: context,
  builder: (_) => _CorrectionSheet(row: row),
);
```

## Key Observation

A bottom sheet does not move up for the keyboard by
default. It also has a height limit unless told otherwise.

## Solution

Let the sheet take the space it needs and pad it by the
keyboard height:

``` dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  builder: (_) => _CorrectionSheet(row: row),
);

Padding(
  padding: EdgeInsets.fromLTRB(
    24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom,
  ),
  ...
)
```

**Because**

`viewInsets.bottom` is the height the keyboard takes up.
Adding it as padding keeps the field and the button above
the keyboard.
