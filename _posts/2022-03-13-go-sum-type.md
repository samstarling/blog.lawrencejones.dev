---
layout: post
title:  "Hacking sum types with Go generics"
date:   "2022-03-13 12:00:00 +0000"
image:  /assets/images/go-sum-type-social.png
hackernews: null  # TODO
tags:
  - golang
excerpt: |
  <p>
    Go doesn't have sum types, but generics get us one step closer to a useful
    polyfill. If you've ever wanted exhaustive case statements, this post is for
    you.
  </p>

---

[incident]: https://incident.io/

I've been writing Go professionally for five years now, and the feature I've
wanted the most -- more than generics, even -- is a sum type.

Specifically, I want to define a type comprising several distinct values, and to
write code that handles all possible values of that type which is checked by the
compiler.

Such a type is key in large projects where the compiler should help you find
modules that need updating when you extend the base sum type. With generics in
go 1.18, it's possible to write an ergonomic switch statement that can help
polyfill for sum types, until they are supported properly.

I walk through how to build this below, but here's a preview of the end result:

```go
// Handle all possible field types:
block, err := CustomFieldTypeSwitch(fieldType,
  func(CustomFieldTypeSwitchOption) (*slack.InputBlock, error) {
    // option fields
  },
  func(CustomFieldTypeSwitchText) (*slack.InputBlock, error) {
    // text fields
  },
  func(CustomFieldTypeSwitchLink) (*slack.InputBlock, error) {
    // link fields
  },
  func(CustomFieldTypeSwitchNumeric) (*slack.InputBlock, error) {
    // numeric fields
  },
)
```

# Real example

[incident.io][incident] provides a custom fields feature, where customers
configure a number of fields that can be set as metadata against each of their
incidents.

Until recently you could only create 'option' custom fields, where the field can
be set to one or more of some user provided options. Imagine you wanted to track
which teams were involved in responding to an incident: that's perfect for an
option type, as you can prefill the teams in advance.

![Screenshot of the incident.io settings where you can create custom fields](
  /assets/images/go-sum-type-custom-field.png
)

[changelog]: https://incident.io/changelog/2022-03-09

Last week we [released support for several new custom field types][changelog]:
freeform text, URL links, and numbers. In an ideal world, we'd extend the sum
type that defines a custom field type, then have the compiler tell us which
parts of the code (Slack app? frontend forms? API?) needed updating to support
the new types.

We tend to model string enums as a custom string type, and enumerate their
options as constants. Adding text, link and numeric types looked like this:

```go
package domain

type CustomFieldType string

const (
  CustomFieldTypeOption    CustomFieldType = "option"
  CustomFieldTypeText      CustomFieldType = "text"
  CustomFieldTypeLink      CustomFieldType = "link"
  CustomFieldTypeNumeric   CustomFieldType = "numeric"
)
```

Then our code would implement support for each type, using a switch statement:

```go
// parseValue parses a string value into Value, as per the custom
// field type.
func parseValue(fieldType CustomFieldType, data string) (*Value, error) {
  switch fieldType {
  case CustomFieldTypeOption:
    return &Value{OptionID: data}, nil

  case CustomFieldTypeText:
    return &Value{Text: data}, nil

  case CustomFieldTypeNumeric:
    value, err := strconv.ParseFloat(data, 64)
    if err != nil {
      return nil, errors.New("invalid value, must be a number")
    }

    return &Value{Numeric: value}, nil

  case CustomFieldTypeLink:
    res, err := url.Parse(data)
    if err != nil {
      return nil, errors.Wrap(err, "failed to parse URL")
    }
    switch res.Scheme {
    case "http", "https":
      // valid
    default:
      return nil, errors.New(
        "invalid link format, must be http or https")
    }

    return &Value{Link: data}, nil

  default:
    return nil, errors.New("unhandled field type: %s", fieldType)
  }
}
```

This... kinda worked. As a general rule of thumb, you'd write the switch
statement and handle an unrecognised/unsupported type in the `default` branch,
usually returning an error complaining about the bad value.

Writing this sucked, though. As I implemented each new type, I'd only discover
parts of the code I had missed by manually testing all key custom field flows,
of which there are about ten. And things like our async Slack notifications
would error in local development, but were easy to miss if you weren't looking
at the logs.

# Hacking the (type) system

It's both error prone and a waste of developer time to manually check the
codebase for each `fieldType` switch. Much better to elevate an unhandled case
to the type system, so the compiler can check this for us.

We can do that by writing our own switch helper:

```go
// These types are used solely to help readability of the
// CustomFieldTypeSwitch helper.
type (
  CustomFieldTypeSwitchOption  CustomFieldType
  CustomFieldTypeSwitchText    CustomFieldType
  CustomFieldTypeSwitchLink    CustomFieldType
  CustomFieldTypeSwitchNumeric CustomFieldType
)

// CustomFieldTypeSwitch is a mechanism to switch over all possible
// values of a CustomFieldType, allowing the compiler to check all
// routes have been handled.
func CustomFieldTypeSwitch[R any](fieldType CustomFieldType,
  option func(CustomFieldTypeSwitchOption) (R, error),
  text func(CustomFieldTypeSwitchText) (R, error),
  link func(CustomFieldTypeSwitchLink) (R, error),
  numeric func(CustomFieldTypeSwitchNumeric) (R, error),
) (res R, err error) {
  switch fieldType {
  case CustomFieldTypeOption:
    if option != nil {
      return option("")
    }
  case CustomFieldTypeText:
    if text != nil {
      return text("")
    }
  case CustomFieldTypeLink:
    if link != nil {
      return link("")
    }
  case CustomFieldTypeNumeric:
    if numeric != nil {
      return numeric("")
    }
  default:
    return res, errors.New(
      "unsupported custom field type: '%s'", fieldType)
  }

  // If we get here, it's because we provided a nil function for a
  // type of custom field, implying we don't want to handle it.
  return res, nil
}
```

This small piece of code:

1. Implements a new type for each of the possible values of `CustomFieldType`
1. Provides `CustomFieldTypeSwitch` that receives a field type, and handlers for
   each possible value

You'd call it like so:

```go
// customFieldToBlock renders a Slack input block for each type of custom field.
func customFieldToBlock(ctx context.Context, entry *CustomFieldEntry) *slack.InputBlock {
  block, err := CustomFieldTypeSwitch(entry.CustomField.FieldType,
    func(CustomFieldTypeSwitchOption) (*slack.InputBlock, error) {
      if entry.CustomField.FieldMulti {
        return multiSelectCustomFieldToBlock(entry), nil
      } else {
        return selectCustomFieldToBlock(entry), nil
      }
    },
    func(CustomFieldTypeSwitchText) (*slack.InputBlock, error) {
      return textCustomFieldToBlock(entry), nil
    },
    func(CustomFieldTypeSwitchLink) (*slack.InputBlock, error) {
      return linkCustomFieldToBlock(entry), nil
    },
    func(CustomFieldTypeSwitchNumeric) (*slack.InputBlock, error) {
      return numericCustomFieldToBlock(entry), nil
    },
  )

  if err != nil {
    log.Warn(ctx, errors.WithMetadata(err, errors.KV{
      "custom_field": entry.CustomField.ID,
    })
  }

  return block
}
```

With this construct, adding a new type will cause a compiler error at every
callsite, as we'll lack support for that new type's handler.

As an example, removing the numeric case causes this error:

```
# github.com/incident-io/core/server/pkg/slack/modal
pkg/slack/modal/custom_field.go:81:3:
  not enough arguments in call to CustomFieldTypeSwitch
  have (CustomFieldType,
    func(CustomFieldTypeSwitchOption) (*slack.InputBlock, error),
    func(CustomFieldTypeSwitchText) (*slack.InputBlock, error),
    func(CustomFieldTypeSwitchLink) (*slack.InputBlock, error)
  )
  want (CustomFieldType,
    func(CustomFieldTypeSwitchOption) (R, error),
    func(CustomFieldTypeSwitchText) (R, error),
    func(CustomFieldTypeSwitchLink) (R, error),
    func(CustomFieldTypeSwitchNumeric) (R, error)
  )
```

Where we have support for option, text, and link, but want a numeric handler
too.

# Taking a closer look

I think there are a few details that make this construct work.

The first is creating new type for each enum value. We don't have to do this for
type-safety: the switch function could take a handler per enum value, and the
compiler would shout if we provided too few handlers.

In my opinion, that would make it much easier to mix up your handlers,
especially as Go doesn't support function keyword arguments. Equally, you can no
longer see which handler is for what type without checking the function
definition, which is a poor experience when reading the code.

Here's the two options side-by-side:

```go
// Without named types (which handler is for which type?):
block, err := CustomFieldTypeSwitch(fieldEntry.CustomField.FieldType,
  func() (*slack.InputBlock, error) {
    //
  },
  func() (*slack.InputBlock, error) {
    //
  },
  func() (*slack.InputBlock, error) {
    //
  },
  func() (*slack.InputBlock, error) {
    //
  },
)

// With named types (it's clear which handler is for which type):
block, err := CustomFieldTypeSwitch(fieldEntry.CustomField.FieldType,
  func(CustomFieldTypeSwitchOption) (*slack.InputBlock, error) {
    //
  },
  func(CustomFieldTypeSwitchText) (*slack.InputBlock, error) {
    //
  },
  func(CustomFieldTypeSwitchLink) (*slack.InputBlock, error) {
    //
  },
  func(CustomFieldTypeSwitchNumeric) (*slack.InputBlock, error) {
    //
  },
)
```

Equally, if you reorder the handlers in your editor, the compiler will shout
unless the function signature matches.

The other detail that adds usability is generic return types. Before generics,
we'd be unable to return values from each case handler without losing
type-safety by passing `interface{}`, or having the handler set a closured
variable.

```go
// Type-casting, losing type-safety:
res, err := CustomFieldTypeSwitch(entry.CustomField.FieldType,
  func(CustomFieldTypeSwitchOption, *slack.InputBlock) error {
    block = new(slack.InputBlock)
  },
  // ...
)
block := res.(*slack.InputBlock) // unsafe

// Setting variable from closure:
var block *slack.InputBlock
err := CustomFieldTypeSwitch(entry.CustomField.FieldType,
  func(CustomFieldTypeSwitchOption) error {
    block = new(slack.InputBlock)
  },
  // ...
)
```

Having considered both of these options before, I'd concluded neither was a
worthwhile trade-off to justify introducing this pattern. Generics help us avoid
these downsides by preserving type-safety for whatever each handler might
return, while maintaining a simple control-flow.

# Closing

The app these code examples reference has a Go backend and a TypeScript
frontend, where the frontend uses a type-safe client to speak to the backend
API.

It has felt very silly that adding an enum value to the Go definition will
codegen a TypeScript enum type, which activates the compiler for non-exhaustive
matches in the frontend, while the backend had no such facility.

I'm hopeful this type of pattern will increase our confidence when working with
the backend, helping us ship faster and feel happier while doing it.
