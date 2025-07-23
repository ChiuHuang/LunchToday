import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const LunchMenuApp());
}

class LunchMenuApp extends StatelessWidget {
  const LunchMenuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '今天午餐吃什麼',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'TW')],
      locale: const Locale('zh', 'TW'),
      home: const LunchMenuHomePage(),
    );
  }
}

class LunchMenuHomePage extends StatefulWidget {
  const LunchMenuHomePage({super.key});

  @override
  State<LunchMenuHomePage> createState() => _LunchMenuHomePageState();
}

class _LunchMenuHomePageState extends State<LunchMenuHomePage> {
  static const String _baseUrl = 'https://fatraceschool.k12ea.gov.tw';
  final TextEditingController _searchController = TextEditingController();

  // Dynamic data storage
  List<School> _schools = [];
  School? _selectedSchool;
  MealData? _currentMeal;
  List<Dish> _dishes = [];
  List<MealHistory> _mealHistory = [];
  Map<String, Color> _dishTypeColors = {};
  Map<String, String> _dishTypeIcons = {};
  Set<String> _allDishTypes = {};

  // State management
  bool _isLoading = false;
  String _errorMessage = '';
  DateTime _selectedDate = DateTime.now();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _initializeDishTypeMapping();
    _loadSavedSchool();
  }

  Future<void> _loadSavedSchool() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSchoolId = prefs.getInt('saved_school_id');
    final savedSchoolName = prefs.getString('saved_school_name');
    final savedSchoolCode = prefs.getString('saved_school_code');

    if (savedSchoolId != null &&
        savedSchoolName != null &&
        savedSchoolCode != null) {
      final savedSchool = School(
        schoolId: savedSchoolId,
        schoolCode: savedSchoolCode,
        schoolName: savedSchoolName,
        countyId: 0,
        areaId: 0,
        schoolType: 0,
      );

      setState(() {
        _selectedSchool = savedSchool;
      });

      _loadTodayMeal();
    }
  }

  Future<void> _saveSchool(School school) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('saved_school_id', school.schoolId);
    await prefs.setString('saved_school_name', school.schoolName);
    await prefs.setString('saved_school_code', school.schoolCode);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _initializeDishTypeMapping() {
    // Base mappings - will be expanded dynamically
    _dishTypeColors = {
      '主食': Colors.brown,
      '主菜': Colors.red,
      '副菜': Colors.green,
      '蔬菜': Colors.lightGreen,
      '湯品': Colors.blue,
      '水果': Colors.orange,
      '飲品': Colors.cyan,
      '點心': Colors.purple,
      '調味料': Colors.grey,
      '配菜': Colors.teal,
      '其他': Colors.grey,
    };

    _dishTypeIcons = {
      '主食': '🍚',
      '主菜': '🍖',
      '副菜': '🥬',
      '蔬菜': '🥗',
      '湯品': '🍲',
      '水果': '🍎',
      '飲品': '🥤',
      '點心': '🍪',
      '調味料': '🧂',
      '配菜': '🥘',
      '其他': '🍽️',
    };
  }

  void _addDishType(String dishType) {
    if (dishType.isEmpty || _allDishTypes.contains(dishType)) return;

    _allDishTypes.add(dishType);

    // Auto-assign color if not exists
    if (!_dishTypeColors.containsKey(dishType)) {
      final colors = [
        Colors.indigo,
        Colors.pink,
        Colors.amber,
        Colors.deepOrange,
        Colors.lime,
        Colors.deepPurple,
        Colors.brown,
        Colors.blueGrey,
        Colors.teal,
        Colors.red.shade300,
        Colors.green.shade300,
      ];
      _dishTypeColors[dishType] = colors[_allDishTypes.length % colors.length];
    }

    // Auto-assign icon if not exists
    if (!_dishTypeIcons.containsKey(dishType)) {
      final icons = ['🍽️', '🥄', '🍴', '🥢', '🍯', '🧈', '🥨', '🍙'];
      _dishTypeIcons[dishType] = icons[_allDishTypes.length % icons.length];
    }
  }

  void _onSearchChanged() {
    if (_searchController.text.trim().length >= 2) {
      _searchSchools();
    } else {
      setState(() {
        _schools = [];
      });
    }
  }

  Future<void> _showDatePicker(BuildContext context) async {
    if (_selectedSchool == null) {
      _showSnackBar('請先選擇學校', Colors.orange);
      return;
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      locale: const Locale('zh', 'TW'),
      helpText: '選擇日期查看午餐菜單',
      cancelText: '取消',
      confirmText: '確認',
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: Colors.orange),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      await _loadMealByDate(picked);
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _loadMealByDate(DateTime date) async {
    if (_selectedSchool == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final dateString = DateFormat('yyyy-MM-dd').format(date);
      final meal = await _fetchMealData(dateString);

      if (meal != null) {
        await _loadDishes(meal.batchDataId);
        setState(() {
          _currentMeal = meal;
          _isLoading = false;
        });
        _showSnackBar(
          '已載入 ${DateFormat('yyyy年MM月dd日').format(date)} 的午餐菜單',
          Colors.green,
        );
      } else {
        setState(() {
          _errorMessage = '${DateFormat('yyyy年MM月dd日').format(date)} 沒有午餐資料';
          _currentMeal = null;
          _dishes = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '載入失敗: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<MealData?> _fetchMealData(String dateString) async {
    final response = await http.get(
      Uri.parse(
        '$_baseUrl/offered/meal?KitchenId=all&MenuType=1&SchoolId=${_selectedSchool!.schoolId}&period=$dateString',
      ),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['result'] == 1 &&
          data['data'] != null &&
          data['data'].isNotEmpty) {
        return MealData.fromJson(data['data'][0]);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '今天午餐吃什麼',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSchoolSelection(),
            const SizedBox(height: 16),
            _buildSelectedSchoolDisplay(),
            const SizedBox(height: 16),
            _buildMainContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildSchoolSelection() {
    if (_selectedSchool != null && !_isSearching)
      return const SizedBox.shrink();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '搜尋學校',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '請輸入學校名稱（至少2個字）',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
            ),
            if (_schools.isNotEmpty) _buildSchoolList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSchoolList() {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          height: 150,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.builder(
            itemCount: _schools.length,
            itemBuilder: (context, index) {
              final school = _schools[index];
              return ListTile(
                title: Text(school.schoolName),
                subtitle: Text('代碼: ${school.schoolCode}'),
                onTap: () => _selectSchool(school),
                selected: _selectedSchool?.schoolId == school.schoolId,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedSchoolDisplay() {
    if (_selectedSchool == null || _isSearching) return const SizedBox.shrink();

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.school,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '已選擇學校',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      Text(
                        _selectedSchool!.schoolName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _isSearching = true;
                      _searchController.clear();
                      _schools = [];
                    });
                  },
                  child: const Text('更換學校'),
                ),
              ],
            ),
            if (_currentMeal != null) _buildCurrentMealInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentMealInfo() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent() {
    if (_isLoading) {
      return const Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('載入中...'),
            ],
          ),
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return _buildErrorView();
    }

    if (_currentMeal != null && _dishes.isNotEmpty) {
      return _buildMealView();
    }

    return _buildEmptyView();
  }

  Widget _buildErrorView() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.restaurant_menu, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              '請先搜尋並選擇學校，然後查看午餐',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: _selectedSchool != null ? _loadTodayMeal : null,
          icon: const Icon(Icons.today),
          label: const Text('今日午餐'),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () => _showDatePicker(context),
          icon: const Icon(Icons.calendar_today),
          label: const Text('選擇日期'),
        ),
      ],
    );
  }

  Widget _buildMealView() {
    return Expanded(
      child: DefaultTabController(
        length: 1, // Changed from 2 to 1
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: '午餐菜單', icon: Icon(Icons.restaurant)),
                // Removed History Tab
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildTodayMealView(),
                  // Removed History View
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayMealView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateCard(),
          const SizedBox(height: 16),
          _buildNutritionCard(),
          const SizedBox(height: 16),
          _buildMenuList(),
        ],
      ),
    );
  }

  Widget _buildDateCard() {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 8),
            Text(
              _formatDateWithWeekday(_currentMeal!.menuDate),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showDatePicker(context),
              icon: const Icon(Icons.edit_calendar),
              label: const Text('更換日期'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.local_fire_department,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '營養資訊',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildNutritionChips(),
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionChips() {
    final nutritionData = _getNutritionData();
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children:
          nutritionData.entries
              .map((entry) => _buildNutritionChip(entry.key, entry.value))
              .toList(),
    );
  }

  Map<String, String> _getNutritionData() {
    final data = <String, String>{};
    if (_currentMeal!.calorie.isNotEmpty)
      data['熱量'] = '${_currentMeal!.calorie} 大卡';
    if (_currentMeal!.typeGrains.isNotEmpty)
      data['全穀雜糧'] = '${_currentMeal!.typeGrains} 份';
    if (_currentMeal!.typeMeatBeans.isNotEmpty)
      data['豆魚蛋肉'] = '${_currentMeal!.typeMeatBeans} 份';
    if (_currentMeal!.typeVegetable.isNotEmpty)
      data['蔬菜'] = '${_currentMeal!.typeVegetable} 份';
    if (_currentMeal!.typeOil.isNotEmpty)
      data['油脂'] = '${_currentMeal!.typeOil} 份';
    if (_currentMeal!.typeFruit.isNotEmpty)
      data['水果'] = '${_currentMeal!.typeFruit} 份';
    if (_currentMeal!.typeMilk.isNotEmpty)
      data['乳品'] = '${_currentMeal!.typeMilk} 份';
    return data;
  }

  Widget _buildMenuList() {
    if (_dishes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '菜單內容 (${_dishes.length} 道菜)',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._dishes.map((dish) => _buildDishCard(dish)).toList(),
      ],
    );
  }

  Widget _buildDishCard(Dish dish) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: _getDishTypeColor(dish.dishType),
              child: Text(
                _getDishTypeIcon(dish.dishType),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(
              dish.dishName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(dish.dishType),
          ),
          if (dish.picturePath.isNotEmpty)
            _buildDishImage(dish.picturePath, dish.dishId),
        ],
      ),
    );
  }

  Widget _buildDishImage(String imagePath, String dishId) {
    // The API is crazy - ignore the broken PicturePath and use DishId directly
    final imageUrls = [
      // Primary pattern: /dish/pic/{DishId}
      '$_baseUrl/dish/pic/$dishId',
      // Try with common extensions
      '$_baseUrl/dish/pic/$dishId.jpg',
      '$_baseUrl/dish/pic/$dishId.jpeg',
      '$_baseUrl/dish/pic/$dishId.png',
      // Fallback to default
      '$_baseUrl/dish/pic/xxxxx',
    ];

    return Container(
      height: 150,
      width: double.infinity,
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _buildImageWithFallback(imageUrls, 0),
      ),
    );
  }

  Widget _buildImageWithFallback(List<String> urls, int index) {
    if (index >= urls.length) {
      print('All image URLs failed for dish image');
      return Container(
        color: Colors.grey[200],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
              SizedBox(height: 8),
              Text('圖片無法載入', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    print('Attempting to load image from: ${urls[index]}');
    return Image.network(
      urls[index],
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          print('Successfully loaded image from: ${urls[index]}');
          return child;
        }
        return Container(
          color: Colors.grey[100],
          child: Center(
            child: CircularProgressIndicator(
              value:
                  loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        print('Failed to load image from: ${urls[index]} - Error: $error');
        // Try next URL if current one fails
        return _buildImageWithFallback(urls, index + 1);
      },
    );
  }

  Widget _buildNutritionChip(String label, String value) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
    );
  }

  Color _getDishTypeColor(String dishType) {
    _addDishType(dishType);
    return _dishTypeColors[dishType] ?? Colors.grey;
  }

  String _getDishTypeIcon(String dishType) {
    _addDishType(dishType);
    return _dishTypeIcons[dishType] ?? '🍽️';
  }

  String _formatDate(String dateString) {
    try {
      final date = DateFormat('yyyy/MM/dd').parse(dateString);
      return DateFormat('yyyy年MM月dd日').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatDateWithWeekday(String dateString) {
    try {
      final date = DateFormat('yyyy/MM/dd').parse(dateString);
      return DateFormat('yyyy年MM月dd日 EEEE', 'zh_TW').format(date);
    } catch (e) {
      return dateString;
    }
  }

  Future<void> _searchSchools() async {
    final query = _searchController.text.trim();

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await http.get(Uri.parse('$_baseUrl/school'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['result'] == 1 && data['data'] != null) {
          final schools =
              (data['data'] as List)
                  .map((school) => School.fromJson(school))
                  .where((school) => school.schoolName.contains(query))
                  .take(20) // Limit results
                  .toList();

          setState(() {
            _schools = schools;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = '搜尋失敗: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _selectSchool(School school) {
    setState(() {
      _selectedSchool = school;
      _currentMeal = null;
      _dishes = [];
      _mealHistory = [];
      _isSearching = false;
    });
    _saveSchool(school); // Save school for next app launch
    _loadTodayMeal();
  }

  Future<void> _loadTodayMeal() async {
    if (_selectedSchool == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _selectedDate = DateTime.now();
    });

    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final meal = await _fetchMealData(today);

      if (meal != null) {
        await _loadDishes(meal.batchDataId);
        setState(() {
          _currentMeal = meal;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = '今日沒有午餐資料';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '載入失敗: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDishes(String batchDataId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/dish?BatchDataId=$batchDataId'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['result'] == 1 && data['data'] != null) {
          final dishes =
              (data['data'] as List)
                  .map((dish) => Dish.fromJson(dish))
                  .toList();

          // Sort dishes by order if available
          dishes.sort((a, b) => a.dishOrder.compareTo(b.dishOrder));

          setState(() {
            _dishes = dishes;
          });

          // Auto-learn dish types
          for (var dish in dishes) {
            _addDishType(dish.dishType);
          }
        }
      }
    } catch (e) {
      print('載入菜單失敗: $e');
    }
  }

  Future<void> _loadMealHistory() async {
    if (_selectedSchool == null) return;

    try {
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 30));
      final startDateString = DateFormat('yyyy-MM-dd').format(startDate);

      final response = await http.get(
        Uri.parse(
          '$_baseUrl/offered/meal?KitchenId=all&MenuType=1&SchoolId=${_selectedSchool!.schoolId}&period=$startDateString',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['result'] == 1 && data['data'] != null) {
          final history =
              (data['data'] as List)
                  .map((meal) => MealHistory.fromJson(meal))
                  .toList();

          // Sort by date (newest first)
          history.sort((a, b) {
            try {
              final dateA = DateFormat('yyyy/MM/dd').parse(a.menuDate);
              final dateB = DateFormat('yyyy/MM/dd').parse(b.menuDate);
              return dateB.compareTo(dateA);
            } catch (e) {
              return 0;
            }
          });

          setState(() {
            _mealHistory = history;
          });
        }
      }
    } catch (e) {
      print('載入歷史記錄失敗: $e');
    }
  }

  Future<void> _loadHistoryMeal(String batchDataId) async {
    setState(() {
      _isLoading = true;
    });

    await _loadDishes(batchDataId);

    setState(() {
      _isLoading = false;
    });
  }
}

// Data models remain the same but with better null safety
class School {
  final int schoolId;
  final String schoolCode;
  final String schoolName;
  final int countyId;
  final int areaId;
  final int schoolType;

  School({
    required this.schoolId,
    required this.schoolCode,
    required this.schoolName,
    required this.countyId,
    required this.areaId,
    required this.schoolType,
  });

  factory School.fromJson(Map<String, dynamic> json) {
    return School(
      schoolId: json['SchoolId'] ?? 0,
      schoolCode: json['SchoolCode'] ?? '',
      schoolName: json['SchoolName'] ?? '',
      countyId: json['CountyId'] ?? 0,
      areaId: json['AreaId'] ?? 0,
      schoolType: json['SchoolType'] ?? 0,
    );
  }
}

class MealData {
  final String batchDataId;
  final int kitchenId;
  final String kitchenName;
  final int schoolId;
  final String schoolCode;
  final String schoolName;
  final String menuDate;
  final int menuType;
  final String menuTypeName;
  final String uploadDateTime;
  final String typeGrains;
  final String typeOil;
  final String typeVegetable;
  final String typeMilk;
  final String typeFruit;
  final String typeMeatBeans;
  final String calorie;

  MealData({
    required this.batchDataId,
    required this.kitchenId,
    required this.kitchenName,
    required this.schoolId,
    required this.schoolCode,
    required this.schoolName,
    required this.menuDate,
    required this.menuType,
    required this.menuTypeName,
    required this.uploadDateTime,
    required this.typeGrains,
    required this.typeOil,
    required this.typeVegetable,
    required this.typeMilk,
    required this.typeFruit,
    required this.typeMeatBeans,
    required this.calorie,
  });

  factory MealData.fromJson(Map<String, dynamic> json) {
    return MealData(
      batchDataId: json['BatchDataId'] ?? '',
      kitchenId: json['KitchenId'] ?? 0,
      kitchenName: json['KitchenName'] ?? '',
      schoolId: json['SchoolId'] ?? 0,
      schoolCode: json['SchoolCode'] ?? '',
      schoolName: json['SchoolName'] ?? '',
      menuDate: json['MenuDate'] ?? '',
      menuType: json['MenuType'] ?? 0,
      menuTypeName: json['MenuTypeName'] ?? '',
      uploadDateTime: json['UploadDateTime'] ?? '',
      typeGrains: json['TypeGrains']?.toString() ?? '',
      typeOil: json['TypeOil']?.toString() ?? '',
      typeVegetable: json['TypeVegetable']?.toString() ?? '',
      typeMilk: json['TypeMilk']?.toString() ?? '',
      typeFruit: json['TypeFruit']?.toString() ?? '',
      typeMeatBeans: json['TypeMeatBeans']?.toString() ?? '',
      calorie: json['Calorie']?.toString() ?? '',
    );
  }
}

class Dish {
  final String dishBatchDataId;
  final String batchDataId;
  final String dishName;
  final String dishType;
  final String dishId;
  final String updateDateTime;
  final int dishOrder;
  final int kitchenId;
  final String picturePath;

  Dish({
    required this.dishBatchDataId,
    required this.batchDataId,
    required this.dishName,
    required this.dishType,
    required this.dishId,
    required this.updateDateTime,
    required this.dishOrder,
    required this.kitchenId,
    required this.picturePath,
  });

  factory Dish.fromJson(Map<String, dynamic> json) {
    return Dish(
      dishBatchDataId: json['DishBatchDataId'] ?? '',
      batchDataId: json['BatchDataId'] ?? '',
      dishName: json['DishName'] ?? '未知菜品',
      dishType: json['DishType'] ?? '其他',
      dishId: json['DishId'] ?? '',
      updateDateTime: json['UpdateDateTime'] ?? '',
      dishOrder: json['DishOrder'] ?? 0,
      kitchenId: json['KitchenId'] ?? 0,
      picturePath: json['PicturePath'] ?? '',
    );
  }
}

class MealHistory {
  final String batchDataId;
  final String menuDate;
  final String menuTypeName;
  final String calorie;

  MealHistory({
    required this.batchDataId,
    required this.menuDate,
    required this.menuTypeName,
    required this.calorie,
  });

  factory MealHistory.fromJson(Map<String, dynamic> json) {
    return MealHistory(
      batchDataId: json['BatchDataId'] ?? '',
      menuDate: json['MenuDate'] ?? '',
      menuTypeName: json['MenuTypeName'] ?? '',
      calorie: json['Calorie']?.toString() ?? '',
    );
  }
}
