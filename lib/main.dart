import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

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
  final TextEditingController _searchController = TextEditingController();
  List<School> _schools = [];
  School? _selectedSchool;
  MealData? _currentMeal;
  List<Dish> _dishes = [];
  List<MealHistory> _mealHistory = [];
  bool _isLoading = false;
  String _errorMessage = '';
  DateTime _selectedDate = DateTime.now();
  bool _isSchoolPickerExpanded = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchSchools();
  }

  Future<void> _showDatePicker(BuildContext context) async {
    if (_selectedSchool == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇學校'), backgroundColor: Colors.orange),
      );
      return;
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)), // 一年前
      lastDate: DateTime.now(),
      locale: const Locale('zh', 'TW'),
      helpText: '選擇日期查看午餐菜單',
      cancelText: '取消',
      confirmText: '確認',
      fieldLabelText: '輸入日期',
      fieldHintText: 'yyyy/mm/dd',
      errorFormatText: '日期格式錯誤',
      errorInvalidText: '無效日期',
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

  Future<void> _loadMealByDate(DateTime date) async {
    if (_selectedSchool == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final dateString = DateFormat('yyyy-MM-dd').format(date);
      final response = await http.get(
        Uri.parse(
          'https://fatraceschool.k12ea.gov.tw/offered/meal?KitchenId=all&MenuType=1&SchoolId=${_selectedSchool!.schoolId}&period=$dateString',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['result'] == 1 && data['data'].isNotEmpty) {
          final meal = MealData.fromJson(data['data'][0]);
          await _loadDishes(meal.batchDataId);

          setState(() {
            _currentMeal = meal;
            _isLoading = false;
          });

          // 顯示成功訊息
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '已載入 ${DateFormat('yyyy年MM月dd日').format(date)} 的午餐菜單',
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          setState(() {
            _errorMessage = '${DateFormat('yyyy年MM月dd日').format(date)} 沒有午餐資料';
            _currentMeal = null;
            _dishes = [];
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = '載入失敗，請稍後再試';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '發生錯誤: $e';
        _isLoading = false;
      });
    }
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
            // 學校搜尋卡片
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isSchoolPickerExpanded = !_isSchoolPickerExpanded;
                        });
                      },
                      child: Row(
                        children: [
                          Text(
                            _selectedSchool == null
                                ? '搜尋學校'
                                : '已選擇: ${_selectedSchool!.schoolName}',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Icon(
                            _isSchoolPickerExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                          ),
                        ],
                      ),
                    ),
                    if (_isSchoolPickerExpanded) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: '請輸入學校名稱（例：XX國小）',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                      if (_schools.isNotEmpty) ...[
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
                                subtitle: Text('學校代碼: ${school.schoolCode}'),
                                onTap: () => _selectSchool(school),
                                selected:
                                    _selectedSchool?.schoolId ==
                                    school.schoolId,
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 選中的學校顯示
            if (_selectedSchool != null)
              Card(
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
                                  style:
                                      Theme.of(context).textTheme.labelMedium,
                                ),
                                Text(
                                  _selectedSchool!.schoolName,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          FilledButton(
                            onPressed: _loadTodayMeal,
                            child: const Text('查看今日午餐'),
                          ),
                        ],
                      ),
                      if (_currentMeal != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_today, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '當前顯示: ${DateFormat('yyyy年MM月dd日').format(DateTime.parse(_currentMeal!.menuDate))}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // 載入指示器
            if (_isLoading)
              const Expanded(
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
              )
            else if (_errorMessage.isNotEmpty)
              Expanded(
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
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _showDatePicker(context),
                        icon: const Icon(Icons.calendar_today),
                        label: const Text('選擇其他日期'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_currentMeal != null && _dishes.isNotEmpty)
              // 午餐菜單顯示
              Expanded(
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: '午餐菜單', icon: Icon(Icons.restaurant)),
                          Tab(text: '歷史記錄', icon: Icon(Icons.history)),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildTodayMealView(),
                            _buildHistoryView(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.restaurant_menu,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '請先搜尋並選擇學校，然後查看午餐',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed:
                                _selectedSchool != null ? _loadTodayMeal : null,
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
                      ),
                    ],
                  ),
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
          // 日期顯示卡片
          Card(
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
                    DateFormat(
                      'yyyy年MM月dd日 EEEE',
                      'zh_TW',
                    ).format(DateTime.parse(_currentMeal!.menuDate)),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
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
          ),

          const SizedBox(height: 16),

          // 營養資訊卡片
          Card(
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _buildNutritionChip('熱量', '${_currentMeal!.calorie} 大卡'),
                      _buildNutritionChip(
                        '全穀雜糧',
                        '${_currentMeal!.typeGrains} 份',
                      ),
                      _buildNutritionChip(
                        '豆魚蛋肉',
                        '${_currentMeal!.typeMeatBeans} 份',
                      ),
                      _buildNutritionChip(
                        '蔬菜',
                        '${_currentMeal!.typeVegetable} 份',
                      ),
                      _buildNutritionChip('油脂', '${_currentMeal!.typeOil} 份'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 菜單列表
          Text(
            '菜單內容',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          ..._dishes
              .map(
                (dish) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
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
                ),
              )
              .toList(),
        ],
      ),
    );
  }

  Widget _buildHistoryView() {
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: _mealHistory.length,
      itemBuilder: (context, index) {
        final history = _mealHistory[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.calendar_today),
            title: Text(
              DateFormat(
                'yyyy年MM月dd日',
              ).format(DateTime.parse(history.menuDate)),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${history.menuTypeName} - ${history.calorie} 大卡'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () => _loadHistoryMeal(history.batchDataId),
          ),
        );
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
    switch (dishType) {
      case '主食':
        return Colors.brown;
      case '主菜':
        return Colors.red;
      case '副菜':
        return Colors.green;
      case '湯品':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getDishTypeIcon(String dishType) {
    switch (dishType) {
      case '主食':
        return '🍚';
      case '主菜':
        return '🍖';
      case '副菜':
        return '🥬';
      case '湯品':
        return '🍲';
      default:
        return '🍽️';
    }
  }

  Future<void> _searchSchools() async {
    if (_searchController.text.trim().isEmpty) {
      setState(() {
        _schools = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await http.get(
        Uri.parse('https://fatraceschool.k12ea.gov.tw/school'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['result'] == 1) {
          final schools =
              (data['data'] as List)
                  .map((school) => School.fromJson(school))
                  .where(
                    (school) => school.schoolName.contains(
                      _searchController.text.trim(),
                    ),
                  )
                  .toList();

          setState(() {
            _schools = schools;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = '搜尋失敗: ${data['message']}';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = '網路錯誤，請稍後再試';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '發生錯誤: $e';
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
    });
  }

  Future<void> _loadTodayMeal() async {
    if (_selectedSchool == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _selectedDate = DateTime.now(); // 重設為今天
    });

    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final response = await http.get(
        Uri.parse(
          'https://fatraceschool.k12ea.gov.tw/offered/meal?KitchenId=all&MenuType=1&SchoolId=${_selectedSchool!.schoolId}&period=$today',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['result'] == 1 && data['data'].isNotEmpty) {
          final meal = MealData.fromJson(data['data'][0]);
          await _loadDishes(meal.batchDataId);
          await _loadMealHistory();

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
      } else {
        setState(() {
          _errorMessage = '載入失敗，請稍後再試';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '發生錯誤: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDishes(String batchDataId) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://fatraceschool.k12ea.gov.tw/dish?BatchDataId=$batchDataId',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['result'] == 1) {
          final dishes =
              (data['data'] as List)
                  .map((dish) => Dish.fromJson(dish))
                  .toList();

          setState(() {
            _dishes = dishes;
          });
        }
      }
    } catch (e) {
      print('載入菜單失敗: $e');
    }
  }

  Future<void> _loadMealHistory() async {
    if (_selectedSchool == null) return;

    try {
      // 載入過去30天的記錄
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 30));

      final response = await http.get(
        Uri.parse(
          'https://fatraceschool.k12ea.gov.tw/offered/meal?KitchenId=all&MenuType=1&SchoolId=${_selectedSchool!.schoolId}&period=${DateFormat('yyyy-MM-dd').format(startDate)}',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['result'] == 1) {
          final history =
              (data['data'] as List)
                  .map((meal) => MealHistory.fromJson(meal))
                  .toList();

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

// 資料模型
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
      schoolId: json['SchoolId'],
      schoolCode: json['SchoolCode'],
      schoolName: json['SchoolName'],
      countyId: json['CountyId'],
      areaId: json['AreaId'],
      schoolType: json['SchoolType'],
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
      batchDataId: json['BatchDataId'],
      kitchenId: json['KitchenId'],
      kitchenName: json['KitchenName'],
      schoolId: json['SchoolId'],
      schoolCode: json['SchoolCode'],
      schoolName: json['SchoolName'],
      menuDate: json['MenuDate'],
      menuType: json['MenuType'],
      menuTypeName: json['MenuTypeName'],
      uploadDateTime: json['UploadDateTime'],
      typeGrains: json['TypeGrains'],
      typeOil: json['TypeOil'],
      typeVegetable: json['TypeVegetable'],
      typeMilk: json['TypeMilk'],
      typeFruit: json['TypeFruit'],
      typeMeatBeans: json['TypeMeatBeans'],
      calorie: json['Calorie'],
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
      dishBatchDataId: json['DishBatchDataId'],
      batchDataId: json['BatchDataId'],
      dishName: json['DishName'],
      dishType: json['DishType'],
      dishId: json['DishId'],
      updateDateTime: json['UpdateDateTime'],
      dishOrder: json['DishOrder'],
      kitchenId: json['KitchenId'],
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
      batchDataId: json['BatchDataId'],
      menuDate: json['MenuDate'],
      menuTypeName: json['MenuTypeName'],
      calorie: json['Calorie'],
    );
  }
}
