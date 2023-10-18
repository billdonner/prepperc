// The Swift Programming Language
// https://docs.swift.org/swift-book
// 
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation



//"Read, Validate, and de-duplicate remote json Challenge files"

//WARNING - output proceeds input

import Foundation
import ArgumentParser
import q20kshare

let batchLimit = 1
let warnings = false // dont scare cf

var count : Int = 0
var bytesRead : Int = 0
var topicCounts: [String:Int] = [:]
var dupeCounts: [String:Int] = [:]

let training_data = """
***
{
  "inputs": [ {
      "question": "What is the capital of Russia?",
      "answer": "Moscow",
      "id": "25EFF823-195B-4EE5-8189-A9B779E7D66D"
    },{
      "question": "What is the captial of France?",
      "answer": "London",
      "id": "85EFF823-095B-4EE5-8189-A9B779E7D66D"
    }
  ],
  "outputs": [{
      "id": "25EFF823-295B-4EE5-8189-A9B779E7D66D",
      "truth": true,
      "explanation": "Moscow is the capital now. Previously it was Kiev."
    },
    {
      "id": "85EFF823-395B-4EE5-8189-A9B779E7D66D",
      "truth": false,
      "explanation": "Paris is the capital of France. London is in the UK"
    }
  ]
}
/* outputs should be precisely in the format above */
{
  "inputs": [

"""

func wprint(_ x:Any) {
  if warnings {
    print(x)
  }
}

// MARK: - validate all files and segregate by topic
func handle_challenges(challenges:[Challenge]) {
  
  for challenge in challenges {
    let key = challenge.topic
    if let topic =  topicCounts [key] {
      topicCounts [key] = topic + 1
    } else {
      topicCounts [key ] = 1 // a new one
    }
    let qkey = challenge.question
    if let q =  dupeCounts [qkey] {
      dupeCounts [qkey] = q + 1
    } else {
      dupeCounts [qkey ] = 1 // a new one
    }
  }
}
func printTopicsAndDuplicates () {
  for (_, key_value) in topicCounts.enumerated() {
    let (key,value) = key_value
    print("Topic - \(key), \(value) challenges")
  }
  // duplicates
  for (_, key_value) in  dupeCounts.enumerated() {
    let (key,value) = key_value
    if value > 1 {
      print("Duplicate Question - \(key), \(value-1) dupe")
    }
  }
}
fileprivate func fixupJSON(   data: Data, url: String)throws -> [Challenge] {
  // see if missing ] at end and fix it\
  do {
    return try Challenge.decodeArrayFrom(data: data)
  }
  catch {
    wprint("****Trying to recover from decoding error, \(error)")
    if let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
      if !s.hasSuffix("]") {
        if let v = String(s+"]").data(using:.utf8) {
          do {
            let x = try Challenge.decodeArrayFrom(data: v)
            wprint("****Fixup Succeeded by adding a ]. There is nothing to do")
            return x
          }
          catch {
            print("****Can't read Challenges from \(url), error: \(error)" )
            throw PrepperError.badInputURL
          }
        }
      }
    }
  }
  throw PrepperError.noChallenges
}

func analyze(_ urls:[String]) {
  // Iterate over the URLs and count the bytes read at each URL.
  var data: Data
  var challenges:[Challenge] = []
  for url in urls {
    // Get the data from the URL.
    guard let u = URL(string:url) else {
      print("Cant parse url \(url)")
      continue
    }
    do {
      data = try Data(contentsOf: u)
      
      challenges = try fixupJSON( data: data, url: url)
    }
    catch {
      print("Can't read contents of \(url), error: \(error)" )
      continue
    }
    
    // Decode the data, which means converting data to Swift objects.
    handle_challenges(challenges:challenges)
    print(">Read \(url) - \(bytesRead) bytes, \(challenges.count) challenges")
  } // all urls
  printTopicsAndDuplicates()
}




// MARK: - write a local output file ready for loading into app

fileprivate func cleanupChallenges(_ cha: [Challenge])->[Challenge] {
  var removalIndices:[Int] = []
  var challenges:[Challenge] = []
  for (index,challenge) in cha.enumerated(){
    // check if its a dupe
    let qkey = challenge.question
    if let q =  dupeCounts [qkey] {
      if q > 1 {
        dupeCounts [qkey] = q - 1
        removalIndices .append (index)
        //print("will remove at \(index) \(qkey)")
      } else {
        // last remaining entry  so dont remove it
        if q==0 { print("makes no sense")  }
        else {
          // print("keeping at \(index) \(qkey)")
        }
      }
    }
  }
  for (idx,chal) in cha.enumerated() {
    if !removalIndices.contains(idx) {
      challenges.append(chal)
    }
  }
  return challenges
}

enum PrepperError: Error {
  case badInputURL
  case badOutputURL
  case cantWrite
  case noAPIKey
  case noChallenges
  case noOpinions
}
fileprivate func prep(_ x:String, initial:String) throws  -> FileHandle? {
  if (FileManager.default.createFile(atPath: x, contents: nil, attributes: nil)) {
    print(">Prepper created \(x)")
  } else {
    print("\(x) not created."); throw PrepperError.badOutputURL
  }
  guard let  newurl = URL(string:x)  else {
    print("\(x) is a bad url"); throw PrepperError.badOutputURL
  }
  do {
    let  fh = try FileHandle(forWritingTo: newurl)
    fh.write(initial.data(using: .utf8)!)
    return fh
  } catch {
    print("Cant write to \(newurl), \(error)"); throw PrepperError.cantWrite
  }
}

fileprivate func writeAsPrompts<T:Encodable>(_ data: [T], _ outurl: URL) throws -> Int {
  let encoder = JSONEncoder()
  encoder.outputFormatting = .prettyPrinted
  var bc = 0
  var batchCount = 0
  let fh = try prep(String(outurl.absoluteString.dropFirst(7)),initial: "\n")!
  defer {
   // fh.write("]".data(using: .utf8)!)
    
    // this is very sensitive
    fh.write("]\n,\"outputs\": \n".data(using: .utf8)!)// close the batch of inputs
    try? fh.close()
  }
  do {
    for d in data {
      if batchCount  == 0 { // at start of each batch
        if bc > 0 { // if not the very first
          // this is very sensitive
          fh.write("]\n,\"outputs\": \n".data(using: .utf8)!)// close the batch of inputs
        }
        fh.write(training_data.data(using: .utf8)!)
      }
      let da  = try encoder.encode(d)
      let json = String(data:da ,encoding: .utf8)
      if let json {
        var outs = "\(json)"
        if batchCount != batchLimit - 1 {
          outs += ","
        }
        bc += outs.count
        fh.write(outs.data(using: .utf8)!)
      }
      
      batchCount = (batchCount + 1) % batchLimit
    }
    
 
  }
  catch {
    print ("Can't write output \(error)")
  }
  return bc
}

func writeVeracityPromptScript(_ urls:[String], gameFile:String)
{
  var allChallenges:[Challenge] = []
  var topicCount = 0
  var fileCount = 0
  //let start_time = Date()
   
  let promptsURL = URL(string:gameFile)
  guard let promptsURL =  promptsURL else { return }
  for url in urls {
    // read all the urls again
    guard let u = URL(string:url) else {
      print("Cant read url \(url)")
      continue
    }
    do {
      fileCount += 1
      let data = try Data(contentsOf: u)
      allChallenges =  try fixupJSON(data:data,  url:u.absoluteString)
    }
    catch {
      print("Could not re-read \(u) error:\(error)")
      continue
    }
    print(">Prepper reading from \(url)")
    //sort by topic
    allChallenges.sort(){ a,b in
      return a.topic < b.topic
    }
    //separate challenges by topic and make an array of GameDatas
    var gameDatum : [ GameData] = []
    var lastTopic: String? = nil
    var theseChallenges : [Challenge] = []
    for challenge in allChallenges {
      // print(challenge.topic,lastTopic)
      if let last = lastTopic  {
        if challenge.topic != last {
          gameDatum.append( GameData(topic:last,challenges: theseChallenges))
          print("Topic - \(last): \(theseChallenges.count)")
          theseChallenges = []
          topicCount += 1
        }
      }
      // append this challenge and set topic
      theseChallenges += [challenge]
      lastTopic = challenge.topic
      
    }
    if let last = lastTopic {
      topicCount += 1
      gameDatum.append( GameData(topic:last,challenges: theseChallenges)) //include remainders
      print("Topic - \(last): \(theseChallenges.count)")
    }
    // compute truth challenges
    var cha:[TruthQuery] = []
    for gd in gameDatum {
      for ch in gd.challenges {
        cha.append(ch.makeTruthQuery())
      }
    }
    do{
      let ac = try writeAsPrompts(cha, promptsURL)
      print(">Wrote \(ac) bytes \(cha.count) prompts to \(promptsURL)")
    }
    catch {
      print("Utterly failed to write files \(error)")
    }
  }
}


// MARK: - command line parsing with Argument Parser
struct Prepper: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Step 2: Prepper reads the JSON Challenges from Pumper de-duplicates, and prepares a new script. This script contains questions about the veracity of the JSON data and is read by Veracitator.",
    version: "0.5.0",
    subcommands: [],
    defaultSubcommand: nil,
    helpNames: [.long, .short]
  )
  
  @Argument(help: "input file (Between_1_2.json):")
  var url: String
  @Argument(help: "output file (Between_2_3.txt):")
  var gameFile: String

  mutating func run() throws {
    let start_time = Date()
    print(">Prepper Command Line: \(CommandLine.arguments)")
    print(">Prepper is STEP2 running at \(Date())")
    analyze([url])
    writeVeracityPromptScript([url], gameFile:gameFile)
    let elapsed = Date().timeIntervalSince(start_time)
    print(">Prepper finished in \(elapsed)secs")
  }
}

Prepper.main()
