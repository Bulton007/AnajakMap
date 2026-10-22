import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';

class SearchResults extends Notifier<List<Json>> {
  @override
  List<Json> build() => const [];
  void replace(List<Json> results) => state = List.unmodifiable(results);
}

final searchResultsProvider = NotifierProvider<SearchResults, List<Json>>(
  SearchResults.new,
);
