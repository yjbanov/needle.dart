/*
Copyright 2013 Google Inc. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
#limitations under the License.
*/

/// Dart port of Needle.js.

import "dart:html";
import "dart:json";
import "dart:collection";
import "dart:typed_data";

class Batch {
  final Uint8List mSamType;
  final List<String> mSamName;
  final Float64List mSamTime;
  Batch(int size):
    mSamType = new Uint8List(size),
    mSamName = new List<String>(size),
    mSamTime = new Float64List(size);
}

class Event {
  int type;
  String name;
  double time;
  String toString() {
    return "Event($type, $name, $time)";
  }
}

typedef BeginFunction(String name);
typedef EndFunction();

Needle needle = new Needle(1000, true);

class Needle {

  int mBatchIndex = 0;    //what's our current batch
  Batch mCurrBatch = null;
  int mArraySize = 2048;  //the size of our bucket of samples
  int mArrayIndex = 0;    //counter in this bucket
  List<Batch> mBatches = [];
  bool mIsHighPrecision = false;

  // public accessors - we use vtable swaps rather than enabled/disabled flags
  BeginFunction begin;
  EndFunction end;

  Needle(int preAllocSamples, this.mIsHighPrecision) {
    this.mBatchIndex = 0;
    this.mArrayIndex = 0;
    this.mBatches.length = 0;

    var numBatches = preAllocSamples / this.mArraySize;
    for(var i =0; i < numBatches; i++) {
        this.addBatch();
    }
    this.mCurrBatch = this.mBatches[0];
  }

  /// Add a batch, mostly internal only...
  addBatch() {
    var btc = new Batch(this.mArraySize);
    this.mCurrBatch = btc;
    this.mBatches.add(btc);
  }

  /// Called at the start of a scope, returns < 1ms precision
  _beginFine(String name) {
    var btch = this.mCurrBatch;

    btch.mSamType[this.mArrayIndex] = 1;
    btch.mSamName[this.mArrayIndex] = name;
    btch.mSamTime[this.mArrayIndex] = window.performance.now();

    this.mArrayIndex++;
    if(this.mArrayIndex  >= this.mArraySize) {
      if(this.mBatchIndex >= this.mBatches.length-1) {
        this.addBatch();
        this.mBatchIndex = this.mBatches.length-1;
      } else {
        this.mBatchIndex++;
        this.mCurrBatch = this.mBatches[this.mBatchIndex];
      }
      this.mArrayIndex = 0;
    }
  }

  // Called at the end of a scope, returns < 1ms precision
  _endFine() {
      var btch = this.mCurrBatch;

      btch.mSamType[this.mArrayIndex] = 2;
      btch.mSamTime[this.mArrayIndex] = window.performance.now();

      this.mArrayIndex++;
      if(this.mArrayIndex  >= this.mArraySize) {
          if(this.mBatchIndex >= this.mBatches.length-1) {
              this.addBatch();
              this.mBatchIndex = this.mBatches.length-1;
          }
          else
          {
              this.mBatchIndex++;
              this.mCurrBatch = this.mBatches[this.mBatchIndex];
          }
          this.mArrayIndex = 0;
      }
  }

   // Called at the start of a scope, returns 1ms precision
  _beginCoarse(String name) {
      var btch = this.mCurrBatch;
      btch.mSamType[this.mArrayIndex] = 1;
      btch.mSamName[this.mArrayIndex] = name;
      btch.mSamTime[this.mArrayIndex] = new DateTime.now().millisecondsSinceEpoch.toDouble();

      this.mArrayIndex++;
      if(this.mArrayIndex  >= this.mArraySize)
      {
          if(this.mBatchIndex >= this.mBatches.length-1)
          {
              this.addBatch();
              this.mBatchIndex = this.mBatches.length-1;
          }
          else
          {
              this.mBatchIndex++;
              this.mCurrBatch = this.mBatches[this.mBatchIndex];
          }
          this.mArrayIndex = 0;
      }
  }

  // Called at the end of a scope, returns 1ms precision.
  _endCoarse() {
      var btch = this.mCurrBatch;
      btch.mSamType[this.mArrayIndex] = 2;
      btch.mSamTime[this.mArrayIndex] = new DateTime.now().millisecondsSinceEpoch.toDouble();

      this.mArrayIndex++;
      if(this.mArrayIndex  >= this.mArraySize)
      {
          if(this.mBatchIndex >= this.mBatches.length-1)
          {
              this.addBatch();
              this.mBatchIndex = this.mBatches.length-1;
          }
          else
          {
              this.mBatchIndex++;
              this.mCurrBatch = this.mBatches[this.mBatchIndex];
          }
          this.mArrayIndex = 0;
      }
  }

  // needle is disabled by default, call this function to
  enable() {
      if(!this.mIsHighPrecision)
      {
          this.begin = this._beginCoarse;
          this.end = this._endCoarse;
      }
      else
      {
          this.begin = this._beginFine;
          this.end = this._endFine;
      }
  }

  // once you've added needle sampling code all over your codebase, you can null it's influence out via calling needle.makeBlunt
  // this will stub out the begin/end functions so that you don't incur overhead
  disable() {
    this.begin = (String name) {};
    this.end = () {};
  }

  // Call this at the end of sampling to get a list of all samples in a usable form
  // don't expect this to be fast; Only call at the end of profiling.
  List<Event> getExportReadyData() {
    var oneArray = <Event>[];
    for (var q = 0; q < this.mBatchIndex; q++) {
        var bkt = this.mBatches[q];
        for(var i = 0; i < this.mArraySize; i++) {
            if(bkt.mSamType[i] == 0) {
                continue;
            }
            var evt = new Event()
                ..type = bkt.mSamType[i]
                ..name = bkt.mSamName[i]
                ..time = bkt.mSamTime[i];
            oneArray.add(evt);
        }
    }

    var bkt = this.mBatches[this.mBatchIndex];
    for(var i = 0; i < this.mArrayIndex; i++) {
        if(bkt.mSamType[i] == 0) {
          continue;
        }
        var evt = new Event()
          ..type = bkt.mSamType[i]
          ..name = bkt.mSamName[i]
          ..time = bkt.mSamTime[i];
        oneArray.add(evt);
    }

    return oneArray;
  }

  // Right now simply dumps linear results out to console; should do something smarter with outputing a about:tracing layout.
  consolePrint(samples) {
    Queue stack = new Queue();
    for (var q =0; q < samples.length; q++) {
      var evt = samples[q];
      if(evt.type == 1) {
          stack.addFirst(evt);
      } else if(evt.type == 2) {
        var lastEvt = stack.removeFirst();
        var delta = (evt.time - lastEvt.time);
        window.console.log(lastEvt.name + ": " + delta.toString() + "ms");
      }
    }
  }

  tracingPrint(samples) {
    var traceString = "[";
    var traceEventGen = (name,time,isStart) {
      var evt = {
        "name": name,
        "pid": 42,
        "tid": "0xBEEF",
        "ts": time,
        "ph": "B"
      };
      if(!isStart) {
        evt["ph"] = "E";
      }
      return stringify(evt);
    };

    var stack = new Queue();
    for (var q =0; q < samples.length; q++) {
      var evt = samples[q];
      if(evt.type == 1) {
        stack.addFirst(evt.name);
        traceString += traceEventGen(evt.name,evt.time,true) + ",\n";
      } else if(evt.type == 2) {
        var nm = stack.removeFirst();
        traceString += traceEventGen(nm,evt.time,false) + ",\n";
      }
    }

    traceString += "{}]";
    return traceString;
  }
}
