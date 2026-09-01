<?php

namespace Pterodactyl\Http\Controllers\Admin\Settings;

use Illuminate\Http\Request;
use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Contracts\Repository\SettingsRepositoryInterface;

class AutoSuspendController extends Controller
{
    protected SettingsRepositoryInterface $settings;

    public function __construct(SettingsRepositoryInterface $settings)
    {
        $this->settings = $settings;
    }

    public function index(): View
    {
        return view('admin.settings.autosuspend', [
            'autosuspendTime' => $this->settings->get('settings::autosuspend:time', '00:00:00'),
        ]);
    }

    public function update(Request $request): RedirectResponse
    {
        $request->validate([
            'autosuspend_time' => 'required|date_format:H:i:s',
        ]);

        $this->settings->set('settings::autosuspend:time', $request->input('autosuspend_time'));

        return redirect()
            ->route('admin.settings.autosuspend')
            ->with('success', 'Waktu Auto Suspend berhasil disimpan.');
    }
}
