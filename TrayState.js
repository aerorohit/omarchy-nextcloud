.pragma library

// The bar instantiates the widget once per screen (Variants over
// Quickshell.screens), but the tray's hidden list is global. Instances share
// this counter so the icon is re-shown only after the last one goes away.
var activeInstances = 0

function acquire() {
  activeInstances += 1
}

function release() {
  if (activeInstances > 0) activeInstances -= 1
  return activeInstances === 0
}
