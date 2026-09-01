@extends('layouts.admin')

@section('title')
    Auto Suspend Time
@endsection

@section('content-header')
    <h1>Auto Suspend<small>Atur jam, menit, detik suspend otomatis.</small></h1>
    <ol class="breadcrumb">
        <li><a href="{{ route('admin.index') }}">Admin</a></li>
        <li><a href="{{ route('admin.settings') }}">Settings</a></li>
        <li class="active">Auto Suspend</li>
    </ol>
@endsection

@section('content')
    <div class="row">
        <div class="col-xs-12">
            <div class="box box-primary">
                <div class="box-header with-border">
                    <h3 class="box-title">Waktu Auto Suspend</h3>
                </div>
                <form action="{{ route('admin.settings.autosuspend') }}" method="POST">
                    @csrf
                    <div class="box-body">
                        @if (session('success'))
                            <div class="alert alert-success">{{ session('success') }}</div>
                        @endif

                        @if ($errors->any())
                            <div class="alert alert-danger">
                                <ul style="margin-bottom: 0;">
                                    @foreach ($errors->all() as $error)
                                        <li>{{ $error }}</li>
                                    @endforeach
                                </ul>
                            </div>
                        @endif

                        <div class="form-group">
                            <label for="pAutosuspendTime" class="control-label">Jam Suspend (HH:MM:SS)</label>
                            <input
                                type="time"
                                step="1"
                                id="pAutosuspendTime"
                                name="autosuspend_time"
                                value="{{ old('autosuspend_time', $autosuspendTime) }}"
                                class="form-control"
                                required
                            />
                            <p class="text-muted small">
                                Server otomatis disuspend begitu jam ini terlewati pada tanggal Expiration Date-nya.
                                Contoh: Expiration Date = 05-09-2026, jam diisi 06:30:00 &rarr; server disuspend mulai
                                05-09-2026 06:30:00 (bukan langsung jam 00:00:00).
                            </p>
                        </div>
                    </div>
                    <div class="box-footer">
                        <button type="submit" class="btn btn-sm btn-primary pull-right">Simpan</button>
                    </div>
                </form>
            </div>
        </div>
    </div>
@endsection
