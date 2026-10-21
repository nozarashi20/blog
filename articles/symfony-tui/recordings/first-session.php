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
