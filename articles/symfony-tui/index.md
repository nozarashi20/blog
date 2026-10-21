# Build interactive terminal interfaces with Symfony TUI

Fabien Potencier presented Symfony TUI at [SymfonyLive Paris 2026](https://live.symfony.com/2026-paris/schedule/keynote). The component provides a widget toolkit for PHP terminal applications.
You compose the screen from widgets, assign keyboard focus, and respond to events. TUI manages terminal input, rendering, and the event loop that keeps the interface active.

We'll use it to build a small log reader. TUI handles navigation, scrolling, and redraws while the application supplies the log entries.

The component is experimental, and the examples use Symfony 8.1. We use a few fixed log entries to leave file loading and parsing aside.

## Create and run a TUI

The TUI runs inside a Symfony Console command, which you're probably already familiar with. The command creates a `Tui` instance to manage the interactive session. It attaches a widget for the initial message and registers a way to stop the session, then calls `run()` to give TUI control of the terminal:

```php
<?php

namespace App\Command;

use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Tui\Event\InputEvent;
use Symfony\Component\Tui\Input\Keybindings;
use Symfony\Component\Tui\Tui;
use Symfony\Component\Tui\Widget\TextWidget;

#[AsCommand(name: 'app:read-log')]
final class ReadLogCommand
{
	public function __invoke(): int
	{
		$tui = new Tui();
		$tui->add(new TextWidget('Log reader. Press q or Ctrl-C to quit.'));

		$keys = new Keybindings(['quit' => ['q', 'ctrl+c']]);
		$tui->addListener(static function (InputEvent $event) use ($tui, $keys): void {
			if ($keys->matches($event->getData(), 'quit')) {
				$event->stopPropagation();
				$tui->stop();
			}
		});

		$tui->run();

		return Command::SUCCESS;
	}
}
```

You run it like any other Symfony Console command:

```sh
php bin/console app:read-log
```

![Animated demonstration of the first TUI session: display the message and quit with q to return to the shell.](./log-reader-session.gif)

The message stays on screen while `run()` keeps the command inside TUI's event loop. The loop processes keyboard input and renders the interface. When the quit listener calls `stop()`, `run()` returns and the command completes with `Command::SUCCESS`. The command does not have to read keys or redraw the screen itself.

TUI enables raw terminal input, so key presses reach the application without waiting for Enter. It manages the cursor and restores the terminal when the session stops, including when an exception leaves the loop.

`Keybindings` groups `q` and Ctrl-C under the action name `quit`. The listener checks each input event for that action. On a match, `stopPropagation()` prevents further handling of that key, and `stop()` ends the session. TUI does not install a default global quit shortcut, so the application provides one before calling `run()`.

## Compose the interface

The reader has to keep track of a selection as the user moves through the log entries. `SelectListWidget` handles selection, navigation, and scrolling, while `TextWidget` displays the heading and keyboard hints.

```php
use Symfony\Component\Tui\Style\Style;
use Symfony\Component\Tui\Widget\SelectListWidget;
```

The command passes three log entries to `SelectListWidget` as an array of items:

```php
$title = new TextWidget('Log entries');
$title->setStyle(new Style(bold: true));

$items = [
	[
		'value' => '0',
		'label' => '10:00:00 INFO',
		'description' => 'app: Application started.',
	],
	[
		'value' => '1',
		'label' => '10:00:05 WARNING',
		'description' => 'doctrine: Slow query.',
	],
	[
		'value' => '2',
		'label' => '10:00:07 ERROR',
		'description' => 'app: Payment failed.',
	],
];
$list = new SelectListWidget($items, maxVisible: 8);

$tui->add($title);
$tui->add($list);
$tui->add(new TextWidget('Up/Down: select | q, Ctrl-C: quit'));
```

An arrow and bold text mark the selected entry. Moving through the list changes that selection and scrolls the items when necessary.

![Animated demonstration of the log reader: launch the command, move down to the error entry, move up, and press Escape to return to the shell.](./log-reader-demo.gif)

Each `add()` attaches a widget to TUI's root `ContainerWidget`. Containers group widgets into a tree. The root's default vertical layout places these widgets in the order they were added, with the title above the list and the help text below it. The title's `Style` changes its appearance.

Each record becomes a list item. Its `label` shows the time and level, and its optional `description` shows the channel and message.

The required `value` identifies the record in our application. We use the original record's index as a string, so `'2'` identifies the payment record. `$list->getSelectedItem()` returns the selected item, including its `value`. Application code can use that identifier without parsing the displayed label.

The outer array's numeric keys serve a different purpose. `SelectListWidget` uses them as positions for selection and rendering, and expects consecutive keys starting at `0`. The payment item is currently at position `2` and has value `'2'`. Its position can change while its `value` continues to identify the payment record.

`maxVisible: 8` displays at most eight items. With a longer list, the widget scrolls to keep the selection visible. This limit does not adjust to the terminal's height, so a short terminal can clip the list or help text. Long descriptions are truncated to fit the available width.

When reading records from a file, we still pass the same `value`, `label`, and `description` fields to the list. These widgets display strings as supplied, including terminal control sequences. The log reader escapes control characters in log text before passing it to the widgets. The fixed strings here contain none.

## Handle keyboard input and focus

The list responds to Down even though the application has no listener for that key. Focus determines which widget receives keyboard input after TUI's global input handling. `SelectListWidget` implements `FocusableInterface`, so TUI can route input to it. The title and help text do not accept keyboard input.

TUI automatically focuses the first focusable widget when it is attached. You can also assign focus explicitly with `$tui->setFocus($list)` before `run()`. Focus belongs to the widget, while selection identifies the current item inside it. Pressing Down changes the selected item without moving focus away from the list.

The quit listener handles input for the whole interface, before any focused widget sees it. `InputEvent::getData()` supplies the terminal input that `Keybindings::matches()` checks against the `quit` bindings.

For Down, the listener does nothing, so the key reaches the focused list. The list uses its own bindings to interpret the key, changes the selection, and updates its display. The application does not need a separate listener for list navigation.

The list's Escape binding dispatches `CancelEvent`. For the log reader, cancelling the list means ending the session, so we connect that event to `stop()`:

```php
$list->onCancel(static fn () => $tui->stop());
```

The global quit listener leaves Escape unhandled, allowing the focused list to interpret it. The widget supplies the cancellation event, and the application decides what cancellation does.

## Filter the list with an input widget

The list already handles navigation and scrolling. We can keep that behavior when filtering by giving it a new set of items after each edit to the query.

`InputWidget` handles single-line text editing, including cursor movement, Backspace, and Ctrl-U to delete back to the start of the line. After each edit, it dispatches a `ChangeEvent` that we can use to update the list.

```php
use Symfony\Component\Tui\Event\ChangeEvent;
use Symfony\Component\Tui\Widget\InputWidget;
```

`$searchText` combines each record's level, channel, and message into one string. Its keys match the record indices stored in the list items' `value` fields. That lets us change the displayed labels without changing what gets searched:

```php
$searchText = [
	'INFO app Application started.',
	'WARNING doctrine Slow query.',
	'ERROR app Payment failed.',
];

$filter = new InputWidget();
$filter->setPrompt('Filter: ');
$filter->onChange(static function (ChangeEvent $event) use ($list, $items, $searchText): void {
	$query = $event->getValue();
	$list->setItems(array_values(array_filter(
		$items,
		static fn (array $item): bool => $query === '' || mb_stripos($searchText[(int) $item['value']], $query) !== false,
	)));
});

$leaveFilter = static fn () => $tui->setFocus($list);
$filter->onSubmit($leaveFilter);
$filter->onCancel($leaveFilter);
```

An edit dispatches `ChangeEvent` with the current text. The callback uses each item's `value` to look up its record's search text. For the payment item, value `'2'` selects `$searchText[2]`.

The callback searches the original items each time, so deleting text can bring records back. `mb_stripos()` matches a substring without regard to case. Typing `AYMENT`, `error`, or `app` can therefore find the payment entry. An empty query includes every item.

`setItems()` invalidates the list's cached rendering, just as `InputWidget` invalidates its own output when text changes. Invalidation marks cached output as out of date and propagates through the parent containers. After handling input, TUI notices the change and schedules a redraw. The callback needs no manual `invalidate()` or `requestRender()` call.

`array_filter()` preserves the original array keys. Filtering for `payment` leaves one item at key `2`, but the widget still starts selection and rendering at key `0`. Without reindexing, the widget would try to read a missing key. `array_values()` puts that result at key `0`, as the list requires. Its `value` remains `'2'`, so it still identifies the payment record.

`setItems()` resets selection to the first result. With no results, `getSelectedItem()` returns `null` and the built-in list displays "No matching items". Clearing the query restores the full list and selects its first item.

After an edit, the input still has focus, so Up and Down do not reach the list. `InputWidget` invokes the `onSubmit()` callback for Enter and the `onCancel()` callback for Escape. Both use `$leaveFilter`, which focuses `$list` without changing the query. Here, cancelling means leaving the input, so Escape keeps the edits already applied to the list.

Our original quit listener now conflicts with text editing. It receives keys before the focused widget, so it would intercept the `q` in `query` and stop the session. TUI already knows which widget has focus. The listener can use that information to keep `q` as a quit shortcut while the list is active and let it become text during editing:

```php
$keys = new Keybindings(['quit' => ['q'], 'interrupt' => ['ctrl+c'], 'filter' => ['/']]);
$tui->addListener(static function (InputEvent $event) use ($tui, $keys, $list, $filter): void {
	$data = $event->getData();
	$browsing = $tui->getFocus() === $list;
	if ($keys->matches($data, 'interrupt') || ($browsing && $keys->matches($data, 'quit'))) {
		$event->stopPropagation();
		$tui->stop();
	} elseif ($browsing && $keys->matches($data, 'filter')) {
		$event->stopPropagation();
		$tui->setFocus($filter);
	}
});
```

The `/` branch moves focus to the input while TUI is still handling the slash. Without `stopPropagation()`, that same key would then reach `InputWidget` and become part of the query. Consuming the shortcut prevents that extra character.

Once the input has focus, `$browsing` is `false`. The listener leaves `/` and `q` unhandled, so `InputWidget` receives them as text. Returning focus to the list makes the shortcuts active again.

The Ctrl-C condition has no `$browsing` check. The listener consumes that key and calls `stop()` regardless of which widget has focus.

The input stays above the list so the query remains visible while browsing. Adding it first also makes it the first focusable widget, which TUI focuses automatically. We explicitly focus `$list` before `run()` so the session starts with list navigation active:

```php
$tui->add($title);
$tui->add($filter);
$tui->add($list);
$tui->add(new TextWidget("List: Up/Down select | / filter | q, Esc quit\nFilter: Enter/Esc return | Ctrl-U clear | Ctrl-C quit anywhere"));
$tui->setFocus($list);
$tui->run();
```

![Animated demonstration of filtering: type query, return to browsing, produce an empty result, clear the query, and quit.](./log-reader-filtering.gif)

## Update the screen while idle

Until now, every change on screen has followed a key press. A session timer needs to keep changing even while the reader is idle. `onTick()` registers a callback that TUI calls without waiting for keyboard input.

The timer uses another `TextWidget`, below the list:

```php
$status = new TextWidget('Session: 0s');
$tui->add($status);
$startedAt = hrtime(true);
$lastSecond = 0;
$tui->onTick(static function () use ($status, $startedAt, &$lastSecond): ?bool {
	$seconds = (int) ((hrtime(true) - $startedAt) / 1_000_000_000);
	if ($seconds !== $lastSecond) {
		$lastSecond = $seconds;
		$status->setText(sprintf('Session: %ds', $seconds));
	}

	return null;
});
```

Each tick checks the elapsed whole seconds. The callback only changes the text when the number changes, so several ticks can pass without updating the widget. As with `setItems()`, `setText()` invalidates the widget's cached rendering. TUI detects that change and schedules a redraw.

Returning `null` keeps idle polling enabled, so TUI continues checking the elapsed time even without keyboard input. The default idle interval is roughly 250 ms. Returning `false` would allow that polling to stop when no other work needs it.

The polling interval and the display's update interval are separate. TUI can tick more often when a redraw is pending, and a busy callback can delay the next tick. Calculating elapsed time from `$startedAt` keeps the timer independent of how many times the callback runs.

The tick callback runs in the same event loop as keyboard input and rendering. Sleeping inside it for a second would also delay key handling for a second. The callback checks the time and returns, leaving the loop free to process input while the timer advances. The loaded log records stay the same throughout the session.

![Animated demonstration of timed updates: the session timer advances while idle and continues while the query is edited.](./log-reader-ticks.gif)

## Conclusion

We've only explored a few of Symfony TUI's features. The component also supports multiline editing, Markdown rendering, and more elaborate layouts through containers and stylesheets.

With the log reader, we've seen how widgets, focus, and the event loop work together inside a familiar Console command. The widgets handle navigation and text editing, while our callbacks connect those interactions to the log records.

Give Symfony TUI a try and see what you can build with it.
