import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Compression algorithms supported
enum CompressionAlgorithm {
  gzip,
  deflate,
  bzip2,
}

/// Service for compressing and decompressing backup data
class CompressionService {
  
  /// Compression level (0-9, where 9 is maximum compression)
  static const int defaultCompressionLevel = 6;
  
  /// Compress data using the specified algorithm
  static Future<CompressedData> compressData(
    Map<String, dynamic> data, {
    CompressionAlgorithm algorithm = CompressionAlgorithm.gzip,
    int compressionLevel = defaultCompressionLevel,
  }) async {
    final jsonString = jsonEncode(data);
    final originalBytes = utf8.encode(jsonString);
    final originalSize = originalBytes.length;
    
    Uint8List compressedBytes;
    String algorithmName;
    
    switch (algorithm) {
      case CompressionAlgorithm.gzip:
        compressedBytes = _compressGzip(originalBytes, compressionLevel);
        algorithmName = 'gzip';
        break;
      case CompressionAlgorithm.deflate:
        compressedBytes = _compressDeflate(originalBytes, compressionLevel);
        algorithmName = 'deflate';
        break;
      case CompressionAlgorithm.bzip2:
        compressedBytes = _compressBzip2(originalBytes, compressionLevel);
        algorithmName = 'bzip2';
        break;
    }
    
    final compressedSize = compressedBytes.length;
    final compressionRatio = originalSize > 0 ? compressedSize / originalSize : 1.0;
    
    return CompressedData(
      data: compressedBytes,
      originalSize: originalSize,
      compressedSize: compressedSize,
      compressionRatio: compressionRatio,
      algorithm: algorithmName,
      compressionLevel: compressionLevel,
      timestamp: DateTime.now(),
    );
  }
  
  /// Decompress data using the specified algorithm
  static Future<Map<String, dynamic>> decompressData(CompressedData compressedData) async {
    Uint8List decompressedBytes;
    
    switch (compressedData.algorithm) {
      case 'gzip':
        decompressedBytes = _decompressGzip(compressedData.data);
        break;
      case 'deflate':
        decompressedBytes = _decompressDeflate(compressedData.data);
        break;
      case 'bzip2':
        decompressedBytes = _decompressBzip2(compressedData.data);
        break;
      default:
        throw CompressionException('Unsupported compression algorithm: ${compressedData.algorithm}');
    }
    
    final jsonString = utf8.decode(decompressedBytes);
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }
  
  /// Compress data in chunks for large datasets
  static Future<CompressedData> compressLargeData(
    Map<String, dynamic> data, {
    CompressionAlgorithm algorithm = CompressionAlgorithm.gzip,
    int compressionLevel = defaultCompressionLevel,
    int chunkSize = 1024 * 1024, // 1MB chunks
  }) async {
    final jsonString = jsonEncode(data);
    final originalBytes = utf8.encode(jsonString);
    final originalSize = originalBytes.length;
    
    // If data is small enough, use regular compression
    if (originalSize <= chunkSize) {
      return compressData(data, algorithm: algorithm, compressionLevel: compressionLevel);
    }
    
    // Compress in chunks
    final compressedChunks = <Uint8List>[];
    int totalCompressedSize = 0;
    
    for (int i = 0; i < originalBytes.length; i += chunkSize) {
      final end = (i + chunkSize < originalBytes.length) ? i + chunkSize : originalBytes.length;
      final chunk = originalBytes.sublist(i, end);
      
      Uint8List compressedChunk;
      switch (algorithm) {
        case CompressionAlgorithm.gzip:
          compressedChunk = _compressGzip(chunk, compressionLevel);
          break;
        case CompressionAlgorithm.deflate:
          compressedChunk = _compressDeflate(chunk, compressionLevel);
          break;
        case CompressionAlgorithm.bzip2:
          compressedChunk = _compressBzip2(chunk, compressionLevel);
          break;
      }
      
      compressedChunks.add(compressedChunk);
      totalCompressedSize += compressedChunk.length;
    }
    
    // Combine all compressed chunks
    final combinedCompressed = Uint8List(totalCompressedSize);
    int offset = 0;
    for (final chunk in compressedChunks) {
      combinedCompressed.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    
    final compressionRatio = originalSize > 0 ? totalCompressedSize / originalSize : 1.0;
    
    return CompressedData(
      data: combinedCompressed,
      originalSize: originalSize,
      compressedSize: totalCompressedSize,
      compressionRatio: compressionRatio,
      algorithm: algorithm.name,
      compressionLevel: compressionLevel,
      timestamp: DateTime.now(),
      isChunked: true,
      chunkSize: chunkSize,
    );
  }
  
  /// Get optimal compression algorithm for given data
  static Future<CompressionAlgorithm> getOptimalAlgorithm(Map<String, dynamic> data) async {
    final jsonString = jsonEncode(data);
    final originalBytes = utf8.encode(jsonString);
    
    // Test different algorithms on a sample
    final sampleSize = (originalBytes.length * 0.1).round().clamp(1024, 10240); // 10% sample, min 1KB, max 10KB
    final sample = originalBytes.take(sampleSize).toList();
    
    final results = <CompressionAlgorithm, double>{};
    
    // Test each algorithm
    for (final algorithm in CompressionAlgorithm.values) {
      try {
        Uint8List compressed;
        switch (algorithm) {
          case CompressionAlgorithm.gzip:
            compressed = _compressGzip(sample, defaultCompressionLevel);
            break;
          case CompressionAlgorithm.deflate:
            compressed = _compressDeflate(sample, defaultCompressionLevel);
            break;
          case CompressionAlgorithm.bzip2:
            compressed = _compressBzip2(sample, defaultCompressionLevel);
            break;
        }
        
        final ratio = compressed.length / sample.length;
        results[algorithm] = ratio;
      } catch (e) {
        // If algorithm fails, give it a poor ratio
        results[algorithm] = 1.0;
      }
    }
    
    // Return algorithm with best compression ratio
    return results.entries.reduce((a, b) => a.value < b.value ? a : b).key;
  }
  
  /// Estimate compression ratio without actually compressing
  static double estimateCompressionRatio(Map<String, dynamic> data) {
    final jsonString = jsonEncode(data);
    
    // Simple heuristic based on data characteristics
    final uniqueChars = jsonString.split('').toSet().length;
    final totalChars = jsonString.length;
    
    // More unique characters = less compression
    final uniqueRatio = uniqueChars / totalChars;
    
    // Estimate compression ratio (this is a rough approximation)
    if (uniqueRatio < 0.1) return 0.3; // Very repetitive data
    if (uniqueRatio < 0.2) return 0.5; // Somewhat repetitive
    if (uniqueRatio < 0.4) return 0.7; // Mixed data
    return 0.9; // Mostly unique data
  }
  
  // Private compression methods
  static Uint8List _compressGzip(List<int> data, int level) {
    final encoder = GZipEncoder();
    final encoded = encoder.encode(data);
    return Uint8List.fromList(encoded ?? data);
  }
  
  static Uint8List _decompressGzip(List<int> data) {
    final decoder = GZipDecoder();
    return Uint8List.fromList(decoder.decodeBytes(data));
  }
  
  static Uint8List _compressDeflate(List<int> data, int level) {
    final encoder = ZLibEncoder();
    return Uint8List.fromList(encoder.encode(data));
  }
  
  static Uint8List _decompressDeflate(List<int> data) {
    final decoder = ZLibDecoder();
    return Uint8List.fromList(decoder.decodeBytes(data));
  }
  
  static Uint8List _compressBzip2(List<int> data, int level) {
    final encoder = BZip2Encoder();
    return Uint8List.fromList(encoder.encode(data));
  }
  
  static Uint8List _decompressBzip2(List<int> data) {
    final decoder = BZip2Decoder();
    return Uint8List.fromList(decoder.decodeBytes(data));
  }
  
  /// Validate compressed data integrity
  static Future<bool> validateCompressedData(CompressedData compressedData) async {
    try {
      final decompressed = await decompressData(compressedData);
      return decompressed.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
  
  /// Get compression statistics for monitoring
  static CompressionStats getCompressionStats(List<CompressedData> compressedDataList) {
    if (compressedDataList.isEmpty) {
      return CompressionStats.empty();
    }
    
    final totalOriginalSize = compressedDataList.fold<int>(0, (sum, data) => sum + data.originalSize);
    final totalCompressedSize = compressedDataList.fold<int>(0, (sum, data) => sum + data.compressedSize);
    final averageRatio = compressedDataList.fold<double>(0, (sum, data) => sum + data.compressionRatio) / compressedDataList.length;
    
    final algorithmCounts = <String, int>{};
    for (final data in compressedDataList) {
      algorithmCounts[data.algorithm] = (algorithmCounts[data.algorithm] ?? 0) + 1;
    }
    
    return CompressionStats(
      totalFiles: compressedDataList.length,
      totalOriginalSize: totalOriginalSize,
      totalCompressedSize: totalCompressedSize,
      averageCompressionRatio: averageRatio,
      spaceSaved: totalOriginalSize - totalCompressedSize,
      algorithmUsage: algorithmCounts,
    );
  }
}

/// Compressed data container
class CompressedData {
  final Uint8List data;
  final int originalSize;
  final int compressedSize;
  final double compressionRatio;
  final String algorithm;
  final int compressionLevel;
  final DateTime timestamp;
  final bool isChunked;
  final int? chunkSize;
  
  const CompressedData({
    required this.data,
    required this.originalSize,
    required this.compressedSize,
    required this.compressionRatio,
    required this.algorithm,
    required this.compressionLevel,
    required this.timestamp,
    this.isChunked = false,
    this.chunkSize,
  });
  
  /// Get formatted original size
  String get formattedOriginalSize {
    return _formatBytes(originalSize);
  }
  
  /// Get formatted compressed size
  String get formattedCompressedSize {
    return _formatBytes(compressedSize);
  }
  
  /// Get space saved
  int get spaceSaved => originalSize - compressedSize;
  
  /// Get formatted space saved
  String get formattedSpaceSaved {
    return _formatBytes(spaceSaved);
  }
  
  /// Get compression percentage
  double get compressionPercentage => (1 - compressionRatio) * 100;
  
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  
  Map<String, dynamic> toJson() {
    return {
      'original_size': originalSize,
      'compressed_size': compressedSize,
      'compression_ratio': compressionRatio,
      'algorithm': algorithm,
      'compression_level': compressionLevel,
      'timestamp': timestamp.toIso8601String(),
      'is_chunked': isChunked,
      'chunk_size': chunkSize,
    };
  }
  
  factory CompressedData.fromJson(Map<String, dynamic> json, Uint8List data) {
    return CompressedData(
      data: data,
      originalSize: json['original_size'] as int,
      compressedSize: json['compressed_size'] as int,
      compressionRatio: json['compression_ratio'] as double,
      algorithm: json['algorithm'] as String,
      compressionLevel: json['compression_level'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isChunked: json['is_chunked'] as bool? ?? false,
      chunkSize: json['chunk_size'] as int?,
    );
  }
  
  @override
  String toString() {
    return 'CompressedData(${formattedOriginalSize} -> ${formattedCompressedSize}, ${compressionPercentage.toStringAsFixed(1)}% saved, $algorithm)';
  }
}

/// Compression statistics
class CompressionStats {
  final int totalFiles;
  final int totalOriginalSize;
  final int totalCompressedSize;
  final double averageCompressionRatio;
  final int spaceSaved;
  final Map<String, int> algorithmUsage;
  
  const CompressionStats({
    required this.totalFiles,
    required this.totalOriginalSize,
    required this.totalCompressedSize,
    required this.averageCompressionRatio,
    required this.spaceSaved,
    required this.algorithmUsage,
  });
  
  factory CompressionStats.empty() {
    return const CompressionStats(
      totalFiles: 0,
      totalOriginalSize: 0,
      totalCompressedSize: 0,
      averageCompressionRatio: 0.0,
      spaceSaved: 0,
      algorithmUsage: {},
    );
  }
  
  /// Get formatted total original size
  String get formattedTotalOriginalSize {
    return _formatBytes(totalOriginalSize);
  }
  
  /// Get formatted total compressed size
  String get formattedTotalCompressedSize {
    return _formatBytes(totalCompressedSize);
  }
  
  /// Get formatted space saved
  String get formattedSpaceSaved {
    return _formatBytes(spaceSaved);
  }
  
  /// Get overall compression percentage
  double get overallCompressionPercentage {
    return totalOriginalSize > 0 ? ((totalOriginalSize - totalCompressedSize) / totalOriginalSize) * 100 : 0.0;
  }
  
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  
  @override
  String toString() {
    return 'CompressionStats(files: $totalFiles, ${formattedTotalOriginalSize} -> ${formattedTotalCompressedSize}, ${overallCompressionPercentage.toStringAsFixed(1)}% saved)';
  }
}

/// Exception thrown when compression operations fail
class CompressionException implements Exception {
  final String message;
  final String? code;
  final Exception? originalException;
  
  const CompressionException(this.message, {this.code, this.originalException});
  
  @override
  String toString() => 'CompressionException: $message${code != null ? ' (Code: $code)' : ''}';
}