# Photo Filter Studio

> [!NOTE]
>
> You can access the finished code on the [solution branch](https://github.com/cis1951/lec9-concurrency/tree/solution).

This repo contains the starter code for **Lecture 9: Concurrency**.

Here, we're building an app that applies a comic-book filter to a grid of twelve Penn campus photos. The filter is written in plain Swift and is *slow on purpose* (a few seconds for all twelve photos), which makes it a perfect guinea pig: we'll run it in the worst possible way first, then move it off the main actor, then run it on all CPU cores at once, and finally break (and fix!) a counter that several tasks share.

Above the grid, the app shows how long the last run took and how many of the filter's small 6×6-pixel tiles were counted (that number only matters from Step 5 on). In the top-left corner, a small fan spins for as long as the main actor is free: it's the app's **heartbeat**, and if it stops, the app is frozen.

Here's a walkthrough of the steps we cover in lecture:

## Step 0: Take the tour

Build and run the app on an iPhone simulator (the project targets iOS 26, so you'll need Xcode 26 or later). You should see the fan spinning in the top-left corner, twelve photos, and three buttons in the bottom bar that don't do anything yet. **Reset** in the top right puts the original photos back at any time.

Have a look around the project:

* `Models/Photo.swift` - a photo and, once we have one, its filtered version.
* `Models/TileCounter.swift` - a counter we'll share between tasks in Step 5.
* `Filters/PixelFilter.swift` - the filter. You don't need to understand (or edit) the math. The only parts we'll use are `PixelFilter.apply(to:)`, and later `tileCount`, `filterTile(_:)` and `result`.
* `View Models/StudioViewModel.swift` - this is where we'll do all our work. It has three empty methods, one per button.
* `Views/RootView.swift` - the grid, the two numbers above it, and the toolbar buttons. `Views/HeartbeatView.swift` is the fan: a `TimelineView(.animation)` asks the main actor to redraw it on every frame, so it stops the moment the main actor is busy.

Before we write any code, one thing about the project settings. Open the project file, select the target, go to **Build Settings** and search for *Default Actor Isolation*. It's set to **MainActor**, which is the default for new Xcode projects (Xcode 26 and later). It means that *everything* in this app - every class, struct and function - runs on the **main actor** unless we explicitly say otherwise.

So what's an actor? An actor is an object that protects its data by making code *take turns*: only one piece of code can run on an actor at a time. The main actor is the actor that owns everything to do with the UI - drawing views, handling taps, and all of our SwiftUI code. Code that runs on the main actor runs on the **main thread**. (The two are closely related, but not the same thing: your code talks to the main actor; the thread is a lower-level implementation detail.)

> **Food for thought:** If only one piece of code can run on the main actor at a time, what happens to the UI while a long piece of code is running on it? Let's find out.

## Step 1: Filter on the main actor

Let's start with the most obvious code: a loop over the photos. In `StudioViewModel`, fill in `filterOnMainActor`:
```swift
func filterOnMainActor() {
    let start = ContinuousClock.now
    for i in photos.indices {
        photos[i].filtered = PixelFilter.apply(to: photos[i].original)
    }
    elapsed = start.duration(to: .now)
}
```

`ContinuousClock` is Swift's stopwatch: we note the time before the loop, and the duration since then after it.

Run the app and tap **Main Actor** in the bottom bar. The fan stops. The photos don't change. You can't even scroll. After a few seconds everything comes back at once: twelve filtered photos, and a *Last run* of around 4 seconds.

What happened? `StudioViewModel` runs on the main actor, so our loop did too. For those 4 seconds the main actor was busy filtering, so it couldn't take its turn at drawing the fan, updating the grid, or handling your touches. This is the number one rule of app development: **never block the main actor**.

> **Understanding check:** We set `photos[i].filtered` inside the loop, so why didn't the photos update one at a time?

> **Some history:** Before Swift had actors, iOS developers talked about the *main thread* and *Grand Central Dispatch* (GCD): you put work on a `DispatchQueue`, and `DispatchQueue.main` was the queue for the main thread. You'll still see this in older code and Stack Overflow answers, and we'll see an example in Step 3.

## Step 2: Move the work off the main actor

The filter has to run somewhere, but it doesn't have to be the main actor. Let's write a function that does one photo *in the background*. Add this to `StudioViewModel`, below `filterInBackground`:
```swift
@concurrent
func render(_ image: UIImage) async -> UIImage {
    PixelFilter.apply(to: image)
}
```

Two new things here:

* `async` means this function can *suspend*: a caller has to `await` it, and while they wait, their actor is free to do other things. You saw this with `URLSession` last lecture.
* `@concurrent` means "don't run this on the caller's actor - run it on a background thread". (`@concurrent` only works on `async` functions.)

Now fill in `filterInBackground` so it calls `render` for each photo:
```swift
func filterInBackground() {
    Task {
        let start = ContinuousClock.now
        for i in photos.indices {
            photos[i].filtered = await render(photos[i].original)
        }
        elapsed = start.duration(to: .now)
    }
}
```

We need a `Task` because `await` is only allowed inside an asynchronous context, and a button action isn't one (this is the same `Task { }` you used inside `.onAppear` last lecture).

Run the app, tap **Reset**, then tap **Background**. The fan keeps spinning, you can scroll, and the photos fill in one by one, top to bottom. *Last run* still says about 4 seconds: it's the same amount of work - it's just not on the main actor anymore.

The `await` is the key. It marks a **suspension point**: the task pauses there until `render` returns. While it's paused, the main actor isn't waiting around - it's free to draw frames and handle touches. When `render` finishes, the task picks up right where it left off, assigns the result, and goes around the loop again.

> **Understanding check:** Step 1 and Step 2 took the same amount of time. What did we gain?

## Step 3: Who runs where?

Let's trace through `filterInBackground` line by line, because every line runs somewhere specific:

```swift
Task {                                       // starts on the main actor (where it was created)
    let start = ContinuousClock.now          // main actor
    for i in photos.indices {                // main actor
        photos[i].filtered =                 // main actor, after the await
            await render(photos[i].original) // render runs on a background thread
    }
    elapsed = start.duration(to: .now)       // main actor
}
```

Notice that we never had to say "go back to the main actor". `StudioViewModel` is isolated to the main actor, so after each `await`, Swift automatically hops back to it before running the next line. That's why assigning to `photos[i].filtered` (which changes the UI) is safe.

**Try it:** delete the `@concurrent` line above `render`, run, and tap **Background**. The fan freezes again! Without `@concurrent`, `render` is just another main-actor method: `async` only means *can pause*, not *runs somewhere else*. Now try replacing `@concurrent` with `nonisolated` instead. Still frozen! In this project (thanks to the *Approachable Concurrency* build setting), a `nonisolated` async function runs on whichever actor called it - and we called it from the main actor. Put `@concurrent` back before moving on.

> **Other ways to run code on the main actor.** Our view model gets this for free, but when you're in a background function (say, inside `render`) and need to update the UI, you'll see three ways of hopping over:
> ```swift
> await MainActor.run { photos[i].filtered = image }      // hop to the main actor, run this, hop back
> Task { @MainActor in photos[i].filtered = image }       // start a new task on the main actor (and don't wait for it)
> DispatchQueue.main.async { self.photos[i].filtered = image } // the old GCD way: "run this on the main thread, later"
> ```
> `@MainActor` can also go on a whole function or class to say "this always runs on the main actor" - which is exactly what the project's default isolation setting does for everything in this app.

## Step 4: Do all twelve at once with a task group

Four seconds is still four seconds. But this Mac has several CPU cores, and `render` only uses one of them at a time. Each photo is independent, so let's filter them all *at the same time*.

Swift's tool for "run a bunch of things in parallel and wait for all of them" is a **task group**. Fill in `filterInParallel`:
```swift
func filterInParallel() {
    Task {
        let start = ContinuousClock.now
        await withTaskGroup { group in
            for (index, photo) in photos.enumerated() {
                group.addTask {
                    (index, await self.render(photo.original))
                }
            }
            for await (index, image) in group {
                photos[index].filtered = image
            }
        }
        elapsed = start.duration(to: .now)
    }
}
```

Here's how it works:

* `withTaskGroup` creates a group and waits until every task in it has finished.
* `group.addTask` adds a *child task* to the group. We add one per photo, each of which calls `render`. Swift runs as many of them at once as the CPU allows.
* `for await ... in group` hands us each result *as it finishes*. There's no guarantee about the order, which is why each child task returns its `index` along with the image.

Run the app, reset, and tap **Parallel**. The photos finish in a random order, and *Last run* drops to around a second - on our Mac, 4 to 5 times faster than Step 2.

> **Food for thought:** We have 12 photos, so why isn't it 12 times faster? (Hint: how many cores does your Mac have? And are they all equally fast?)

> **Related: `async let`.** When you have a *fixed* number of things to run in parallel, `async let` is a lighter-weight option:
> ```swift
> async let first = render(photos[0].original)
> async let second = render(photos[1].original)
> photos[0].filtered = await first
> photos[1].filtered = await second
> ```
> Both start immediately; the `await`s wait for them. Use a task group when the number of tasks is only known at runtime, like our array of photos.

## Step 5: Count the tiles - and watch a data race

*Tiles processed* at the top of the screen has been saying 0 this whole time. Let's make it count. Open `Models/TileCounter.swift` and read it:
```swift
nonisolated final class TileCounter: @unchecked Sendable {
    var count = 0

    func increment() {
        count += 1
    }
    ...
}
```

It's a normal class with a number in it. The scary part is `@unchecked Sendable`. `Sendable` is Swift's name for "safe to share between tasks", and the `@unchecked` means we're *promising* Swift that it is, without any proof. Remember that for later.

`StudioViewModel` already has one of these: `let counter = TileCounter()`. We'll have `render` bump it once for every tile it filters. Replace the body of `render` so it processes the photo tile by tile:
```swift
@concurrent
func render(_ image: UIImage) async -> UIImage {
    let filter = PixelFilter(image)
    for tile in 0..<filter.tileCount {
        filter.filterTile(tile)
        counter.increment()
    }
    return filter.result
}
```

Then, in both `filterInBackground` and `filterInParallel`, reset the counter at the start and copy its total into `tilesProcessed` at the end:
```swift
Task {
    let start = ContinuousClock.now
    counter.reset()
    // ... (the loop or task group, unchanged)
    tilesProcessed = counter.count
    elapsed = start.duration(to: .now)
}
```

Run the app and tap **Background**. *Tiles processed* reads 307,200 / 307,200: every tile was counted, exactly as expected. Now reset and tap **Parallel**. The first number comes out *lower*: a few hundred tiles are missing! Tap it a few more times - the number of missing tiles is different every run.

That's a **data race**. `count += 1` looks like one step, but it's really three: *read* the current value, *add* one, *write* it back. With twelve tasks hammering the same counter, two of them regularly read the same value at the same time, both add one, and both write back the same result - and one increment is lost forever. It doesn't crash, it doesn't warn, it's just quietly wrong. Data races are among the hardest bugs to find in any language.

> **Understanding check:** The **Background** button runs the exact same `render` function. Why does it always count correctly?

Swift normally catches code like this. Try deleting `@unchecked Sendable` from `TileCounter` (keep the `nonisolated`) and building: Xcode now flags the `counter.increment()` line in `render` with *main actor-isolated property 'counter' cannot be accessed from outside of the actor; this is an error in the Swift 6 language mode*. Swift knows that handing a plain class from the main actor to a background thread is unsafe. This project uses the Swift 5 language mode, where that's only a warning; in Swift 6 mode it wouldn't compile at all. We only silenced it by promising `@unchecked Sendable`. Put it back - we'll fix this properly in the next step.

## Step 6: Fix it with an actor

A data race needs two things: shared data, and two pieces of code touching it at the same time. We can't avoid the sharing - the whole point of the counter is to be shared. But an actor can rule out the "at the same time" part. Change `TileCounter` from a class into an actor:
```swift
actor TileCounter {
    var count = 0

    func increment() {
        count += 1
    }

    func reset() {
        count = 0
    }
}
```

That's the entire fix for the race. Build, and Xcode flags every line that touches the counter: an error on `counter.increment()` in `render` (*actor-isolated instance method 'increment()' cannot be called from outside of the actor*) and warnings with the same message on the other four. Each one is Xcode telling us "this might have to wait its turn". Add `await` to all five: `counter.increment()` in `render`, and `counter.reset()` and `counter.count` in `filterInBackground` and `filterInParallel`:
```swift
await counter.increment()
await counter.reset()
tilesProcessed = await counter.count
```

Run, reset, and tap **Parallel**. 307,200 / 307,200, every time - and *Last run* is no slower than before.

What happened? An actor only lets one task in at a time. When twelve tasks all call `increment()`, they line up, and each `count += 1` runs start to finish before the next one begins - so no increment can ever be lost. The `await` is where a task waits for its turn (the suspension point), and it's exactly the same mechanism as the main actor in Steps 1 to 3: the main actor is just an actor that the system creates for the UI.

> **Understanding check:** Inside `TileCounter`, `increment()` writes to `count` without any `await`. Why is that allowed?

> **Food for thought:** In Step 4 the photos popped in one at a time, in a random order. Now they all appear at nearly the same moment. Why? (Hint: every task now waits its turn at the counter 25,600 times, so they all move along at the same pace.)

> **Why did the compiler force us to write `await`?** Because an actor's data can only be touched by code *running on that actor*, and getting onto the actor might mean waiting. Code outside the actor therefore has to go through an `async` call. This is called *actor isolation*, and it's the same reason the compiler rejected our non-`Sendable` counter in Step 5: Swift tracks which actor every piece of data belongs to, and only lets you share things that are safe to share.

## Where to go from here

* **Cancellation.** Tap **Parallel** and then **Reset** while it's still running. The reset happens, but the filtered photos still show up a moment later: nothing stops the tasks. Look up `Task.isCancelled` and `Task.checkCancellation()`, and think about where `render` would check them.
* **Taking turns has a cost.** Our actor handles 307,200 `increment()` calls per run and it's fine here, but an actor is a line that tasks wait in. If a counter were slowing down a real app, you'd count locally inside each task and update the actor once per photo.
* **Swift 6 language mode.** This project uses the Swift 5 language mode. Switch *Swift Language Version* to 6 in the build settings and Swift's data-race checking becomes an error on every line, not just a warning - which is why `@unchecked Sendable` was needed to make Step 5 compile at all.

## Photo credits

All photos are from Wikimedia Commons, cropped to squares and scaled down for this app.

| Photo | Title | Author | License |
| --- | --- | --- | --- |
| College Hall | [College Hall, University of Pennsylvania, 2010](https://commons.wikimedia.org/wiki/File:College_Hall,_University_of_Pennsylvania,_2010.jpg) | Smallbones | [CC0](https://creativecommons.org/publicdomain/zero/1.0/) |
| Fisher Fine Arts Library | [Fisher Fine Arts Library - UPenn](https://commons.wikimedia.org/wiki/File:Fisher_Fine_Arts_Library_-_UPenn_(53590493459).jpg) | ajay_suresh | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) |
| LOVE Statue | [Love Statue](https://commons.wikimedia.org/wiki/File:Love_Statue.jpg) | Kevin83002 | Public domain |
| Locust Walk | [Locust Walk - UPenn](https://commons.wikimedia.org/wiki/File:Locust_Walk_-_UPenn_(53589301557).jpg) | ajay_suresh | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) |
| Ben Franklin Statue | [Statue of Benjamin Franklin (UPenn)](https://commons.wikimedia.org/wiki/File:Statue_of_Benjamin_Franklin_(UPenn).JPG) | Padraig Singal | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) |
| Houston Hall | [The Spruce Street Entrance of the Houston Hall of the University of Pennsylvania](https://commons.wikimedia.org/wiki/File:The_Spruce_Street_Entrance_of_the_Houston_Hall_of_the_University_of_Pennsylvania.jpg) | AttaleianAnatolian | [CC0](https://creativecommons.org/publicdomain/zero/1.0/) |
| The Quad | [University of Pennsylvania Lower Quad Freshman Dormitory](https://commons.wikimedia.org/wiki/File:University_of_Pennsylvania_Lower_Quad_Freshman_Dormitory.jpg) | Cspstar | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) |
| Irvine Auditorium | [Irvine Auditorium - UPenn](https://commons.wikimedia.org/wiki/File:Irvine_Auditorium_-_UPenn_(53590619400).jpg) | ajay_suresh | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) |
| Penn Museum | [Penn Museum's Warden Garden and Main Entrance, Summer 2012](https://commons.wikimedia.org/wiki/File:Penn_Museum%27s_Warden_Garden_and_Main_Entrance,_Summer_2012.jpg) | Mefman00 | [CC0](https://creativecommons.org/publicdomain/zero/1.0/) |
| Huntsman Hall | [UPenn - The Wharton School of Business - Huntsman Hall](https://commons.wikimedia.org/wiki/File:UPenn_-_The_Wharton_School_of_Business_-_Huntsman_Hall_(53590621660).jpg) | ajay_suresh | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) |
| Franklin Field | [Penn's Class of 2027 Convocation](https://commons.wikimedia.org/wiki/File:Penn%27s_Class_of_2027_Convocation.jpg) | DfbJZ | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| Van Pelt Library | [Van Pelt Library - UPenn](https://commons.wikimedia.org/wiki/File:Van_Pelt_Library_-_UPenn_(53590176501).jpg) | ajay_suresh | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) |
