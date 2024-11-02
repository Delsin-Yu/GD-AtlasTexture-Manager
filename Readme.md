# AtlasTexture Manager for Godot

Supported Godot Version: 4.3 or later.

![image](https://github.com/user-attachments/assets/ebd07d5c-d287-45e1-9722-8f3cd11d7974)

## Installation

1. Download the `GD-AtlasTexture-Manager.zip` from the latest [release](https://github.com/Delsin-Yu/GD-AtlasTexture-Manager/releases).
2. Decompress the file and place the `addons` directory into the project root (`res://`).
3. In Godot Editor, navigate to `Project/Project Settings/Plugins`, locate the `AtlasTexture Manager` from the `Installed Plugins` list, and check the `Enable` box under the `Status` column.
4. The `AtlasTexure Manager` will launch at the `Bottom Panel`.

## Guide

### Inspect a Texture2D Resource in the `AtlasTexture Manager`

Double-clicking a `Texture2D` resource in the `FileSystem` window will send it to the active `AtlasTexture Manager` window, allowing the developer to modify it further.

https://github.com/user-attachments/assets/f60db0d0-9b6e-48ca-bff0-fd93385ff8dc

### Scan the AtlasTextures that belong to a Texture2D Resource

To scan for `AtlasTextures` that references the inspecting `Texture2D`, use the `Scan in Directory` or `Scan in Project` button. This will search and display the region of the eligible `AtlasTextures` in the inspector.

https://github.com/user-attachments/assets/969eef07-5ec0-4f1d-ad3e-bfa959b89afd

### Create AtlasTextures from a Texture2D Resource

The AtlasTexture Manager offers two approaches to creating AtlasTextures: using `Slicers` or manually specifying the slice area.

#### AtlasTexture Slicers

There are three built-in slicers, each for a specific use case.

##### Cell Count Slicer

Create `AtlasTextures` by specifying how many `columns` and `rows` the current `Texture2D` resource contains.

https://github.com/user-attachments/assets/4dff2dda-0163-4e2d-bc51-51c57431fcb9

##### Cell Size Slicer

Create `AtlasTextures` by specifying the size of each element the current `Texture2D` resource contains.

https://github.com/user-attachments/assets/018e6dc4-a9f3-41a6-9cd7-b4210573ca89

##### Automatic Slicer

Create `AtlasTextures` by automatically detecting the content the current `Texture2D` resource contains.

https://github.com/user-attachments/assets/7b772ac4-19bf-48c1-b1f0-f6384a7781d0

#### Create AtlasTexture Manually

Click and hold the left mouse button, then drag towards the inspector's bottom right to specify the target's range `AtlasTextures`.

https://github.com/user-attachments/assets/c2105972-f22b-4b33-bffe-961916282963

### Editing the Properties of an AtlasTexture

Click an existing `AtlasTexture` region inside the inspector will show its properties in the bottom right inspector; editing these values will mark the region `modified`; to write the changes to the actual `AtlasTexture`, the developer needs to [Apply or Discard Modification](#apply-or-discard-modification).

> Developer may only delete a newly created(not yet saved to asset) `AtlasTexture` region.

### Apply or Discard Modification

The `AtlasTexture Manager` will display `newly created` `AtlasTexture` regions `Yellow` and `modified` `AtlasTexture` regions `Green Yellow` to notify there are pending changes.

To apply the changes, click the `Create & Update` button. This will convert all `newly created` `AtlasTexture` regions to actual `AtlasTexture` resources and save them to the same directory of the inspecting `Texture2D` resource. The pending changes to the existing `AtlasTexture` resources will also be applied.

https://github.com/user-attachments/assets/768530d0-c872-4a3a-a05a-519298342cc7

To discard the changes, click the `Discard` button. This will remove all `newly created` `AtlasTexture` regions and restore all the pending changes to the existing `AtlasTexture` resources.

https://github.com/user-attachments/assets/40e95a89-cc63-4333-b808-96547a7423b8
