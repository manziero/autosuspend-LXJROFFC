<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up()
    {
        Schema::table('servers', function (Blueprint $table) {
            $table->dateTime('exp_date')->nullable()->change();
        });
    }

    public function down()
    {
        Schema::table('servers', function (Blueprint $table) {
            $table->date('exp_date')->nullable()->change();
        });
    }
};
