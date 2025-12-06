# core/coordinate_exploration_system.rb
# 좌표 기반 탐색 시스템 - 클라리스 오르 조직 소탕

require 'json'

class CoordinateExplorationSystem
  # 장소별 심층 조사 포인트 정의
  INVESTIGATION_LOCATIONS = {
    'B2' => {
      '창고' => {
        sub_locations: ['상자', '선반', '구석'],
        description: '먼지 쌓인 창고입니다. 여기저기 상자들이 쌓여있습니다.'
      },
      '회의실' => {
        sub_locations: ['회의 테이블', '화이트보드', '서랍'],
        description: '넓은 회의실입니다. 테이블 위에 서류들이 어질러져 있습니다.'
      },
      '대기실' => {
        sub_locations: ['소파', '테이블', '사물함'],
        description: '소박한 대기실입니다. 오래 사용하지 않은 것 같습니다.'
      }
    },
    'B3' => {
      '자료실' => {
        sub_locations: ['책장', '책상', '서랍', '금고'],
        description: '책장이 가득한 자료실입니다. 먼지가 두껍게 쌓여있습니다.'
      },
      '무기고' => {
        sub_locations: ['무기 진열대', '탄약함', '보관함'],
        description: '냉기가 도는 무기고입니다. 제식 무기들이 정렬되어 있습니다.'
      },
      '작전실' => {
        sub_locations: ['작전 지도', '문서함', '통신기'],
        description: '작전실입니다. 벽에 큰 지도가 걸려있습니다.'
      },
      '통신실' => {
        sub_locations: ['통신 장비', '기록함', '암호문서'],
        description: '각종 마법 통신 장비가 있는 통신실입니다.'
      }
    },
    'B4' => {
      '감시실' => {
        sub_locations: ['감시 수정구', '기록 장치', '제어 패널'],
        description: '마법 감시실입니다. 수정구들이 희미하게 빛나고 있습니다.'
      },
      '간부실' => {
        sub_locations: ['책상', '금고', '서재', '비밀문'],
        description: '호화로운 간부실입니다. 마법 결계가 느껴집니다.'
      },
      '훈련장' => {
        sub_locations: ['무기 거치대', '훈련 인형', '장비함'],
        description: '넓은 훈련장입니다. 전투 흔적이 곳곳에 있습니다.'
      },
      '비밀창고' => {
        sub_locations: ['보관함', '마법 상자', '비밀 구역'],
        description: '은밀한 비밀창고입니다. 강한 결계가 쳐져있습니다.'
      },
      '마법연구실' => {
        sub_locations: ['연구 테이블', '마법서 보관함', '실험 도구'],
        description: '금지된 마법을 연구하던 곳입니다. 불길한 기운이 감돕니다.'
      }
    },
    'B5' => {
      '비밀문서고' => {
        sub_locations: ['기밀 서가', '금고', '비밀 보관함'],
        description: '조직의 모든 기밀이 보관된 곳입니다. 삼엄한 경계가 느껴집니다.'
      },
      '핵심인물실' => {
        sub_locations: ['책상', '침대', '금고', '비밀 금고'],
        description: '핵심인물의 개인실입니다. 극도로 조심해야 합니다.'
      },
      '금고' => {
        sub_locations: ['주금고', '보조금고', '비밀 구획'],
        description: '조직의 재산이 보관된 금고입니다. 복잡한 마법 자물쇠가 있습니다.'
      },
      '사령관실' => {
        sub_locations: ['작전 테이블', '무기함', '개인 금고'],
        description: '사령관의 집무실입니다. 권위가 느껴지는 공간입니다.'
      },
      '전략실' => {
        sub_locations: ['전략 지도', '문서 보관함', '통신 장비'],
        description: '조직의 전체 전략을 관리하는 곳입니다. 최고 기밀 구역입니다.'
      }
    }
  }

  # 층별 맵 정의 (8x8)
  # 좌표 형식: "층-좌표" (예: B2-A1, B3-C4)
  FLOOR_MAPS = {
    'B2' => {
      name: '지하 2층',
      difficulty: 1,
      investigation_type: '조사',
      entrance: 'B2-F7',
      grid: {
        'B2-A1' => { type: 'wall', name: '벽' },
        'B2-B1' => { type: 'wall', name: '벽' },
        'B2-C1' => { type: 'wall', name: '벽' },
        'B2-D1' => { type: 'wall', name: '벽' },
        'B2-E1' => { type: 'wall', name: '벽' },
        'B2-F1' => { type: 'wall', name: '벽' },
        'B2-G1' => { type: 'wall', name: '벽' },
        'B2-H1' => { type: 'wall', name: '벽' },
        
        'B2-A2' => { type: 'wall', name: '벽' },
        'B2-B2' => { type: 'room', name: '창고', investigatable: true },
        'B2-C2' => { type: 'corridor', name: '복도' },
        'B2-D2' => { type: 'corridor', name: '복도' },
        'B2-E2' => { type: 'corridor', name: '복도' },
        'B2-F2' => { type: 'corridor', name: '복도' },
        'B2-G2' => { type: 'wall', name: '벽' },
        'B2-H2' => { type: 'wall', name: '벽' },
        
        'B2-A3' => { type: 'wall', name: '벽' },
        'B2-B3' => { type: 'corridor', name: '복도' },
        'B2-C3' => { type: 'corridor', name: '복도' },
        'B2-D3' => { type: 'corridor', name: '복도' },
        'B2-E3' => { type: 'corridor', name: '복도' },
        'B2-F3' => { type: 'corridor', name: '복도' },
        'B2-G3' => { type: 'corridor', name: '복도' },
        'B2-H3' => { type: 'wall', name: '벽' },
        
        'B2-A4' => { type: 'wall', name: '벽' },
        'B2-B4' => { type: 'corridor', name: '복도' },
        'B2-C4' => { type: 'room', name: '회의실', investigatable: true },
        'B2-D4' => { type: 'room', name: '회의실', investigatable: true },
        'B2-E4' => { type: 'room', name: '회의실', investigatable: true },
        'B2-F4' => { type: 'corridor', name: '복도' },
        'B2-G4' => { type: 'room', name: '대기실', investigatable: true },
        'B2-H4' => { type: 'wall', name: '벽' },
        
        'B2-A5' => { type: 'wall', name: '벽' },
        'B2-B5' => { type: 'corridor', name: '복도' },
        'B2-C5' => { type: 'corridor', name: '복도' },
        'B2-D5' => { type: 'corridor', name: '복도' },
        'B2-E5' => { type: 'corridor', name: '복도' },
        'B2-F5' => { type: 'corridor', name: '복도' },
        'B2-G5' => { type: 'corridor', name: '복도' },
        'B2-H5' => { type: 'wall', name: '벽' },
        
        'B2-A6' => { type: 'wall', name: '벽' },
        'B2-B6' => { type: 'corridor', name: '복도' },
        'B2-C6' => { type: 'corridor', name: '복도' },
        'B2-D6' => { type: 'corridor', name: '복도' },
        'B2-E6' => { type: 'corridor', name: '복도' },
        'B2-F6' => { type: 'corridor', name: '복도' },
        'B2-G6' => { type: 'corridor', name: '복도' },
        'B2-H6' => { type: 'wall', name: '벽' },
        
        'B2-A7' => { type: 'wall', name: '벽' },
        'B2-B7' => { type: 'corridor', name: '복도' },
        'B2-C7' => { type: 'corridor', name: '복도' },
        'B2-D7' => { type: 'corridor', name: '복도' },
        'B2-E7' => { type: 'corridor', name: '복도' },
        'B2-F7' => { type: 'entrance', name: '입구' },
        'B2-G7' => { type: 'corridor', name: '복도' },
        'B2-H7' => { type: 'wall', name: '벽' },
        
        'B2-A8' => { type: 'wall', name: '벽' },
        'B2-B8' => { type: 'wall', name: '벽' },
        'B2-C8' => { type: 'wall', name: '벽' },
        'B2-D8' => { type: 'wall', name: '벽' },
        'B2-E8' => { type: 'wall', name: '벽' },
        'B2-F8' => { type: 'wall', name: '벽' },
        'B2-G8' => { type: 'wall', name: '벽' },
        'B2-H8' => { type: 'wall', name: '벽' }
      }
    },
    
    'B3' => {
      name: '지하 3층',
      difficulty: 2,
      investigation_type: '정밀조사',
      entrance: 'B3-F7',
      grid: {
        'B3-A1' => { type: 'wall', name: '벽' },
        'B3-B1' => { type: 'wall', name: '벽' },
        'B3-C1' => { type: 'wall', name: '벽' },
        'B3-D1' => { type: 'wall', name: '벽' },
        'B3-E1' => { type: 'wall', name: '벽' },
        'B3-F1' => { type: 'wall', name: '벽' },
        'B3-G1' => { type: 'wall', name: '벽' },
        'B3-H1' => { type: 'wall', name: '벽' },
        
        'B3-A2' => { type: 'wall', name: '벽' },
        'B3-B2' => { type: 'room', name: '자료실', investigatable: true },
        'B3-C2' => { type: 'corridor', name: '복도' },
        'B3-D2' => { type: 'corridor', name: '복도' },
        'B3-E2' => { type: 'corridor', name: '복도' },
        'B3-F2' => { type: 'corridor', name: '복도' },
        'B3-G2' => { type: 'room', name: '무기고', investigatable: true },
        'B3-H2' => { type: 'wall', name: '벽' },
        
        'B3-A3' => { type: 'wall', name: '벽' },
        'B3-B3' => { type: 'corridor', name: '복도' },
        'B3-C3' => { type: 'corridor', name: '복도' },
        'B3-D3' => { type: 'corridor', name: '복도' },
        'B3-E3' => { type: 'corridor', name: '복도' },
        'B3-F3' => { type: 'corridor', name: '복도' },
        'B3-G3' => { type: 'corridor', name: '복도' },
        'B3-H3' => { type: 'wall', name: '벽' },
        
        'B3-A4' => { type: 'wall', name: '벽' },
        'B3-B4' => { type: 'corridor', name: '복도' },
        'B3-C4' => { type: 'room', name: '작전실', investigatable: true },
        'B3-D4' => { type: 'room', name: '작전실', investigatable: true },
        'B3-E4' => { type: 'room', name: '통신실', investigatable: true },
        'B3-F4' => { type: 'room', name: '통신실', investigatable: true },
        'B3-G4' => { type: 'corridor', name: '복도' },
        'B3-H4' => { type: 'wall', name: '벽' },
        
        'B3-A5' => { type: 'wall', name: '벽' },
        'B3-B5' => { type: 'corridor', name: '복도' },
        'B3-C5' => { type: 'corridor', name: '복도' },
        'B3-D5' => { type: 'corridor', name: '복도' },
        'B3-E5' => { type: 'corridor', name: '복도' },
        'B3-F5' => { type: 'corridor', name: '복도' },
        'B3-G5' => { type: 'corridor', name: '복도' },
        'B3-H5' => { type: 'wall', name: '벽' },
        
        'B3-A6' => { type: 'wall', name: '벽' },
        'B3-B6' => { type: 'corridor', name: '복도' },
        'B3-C6' => { type: 'corridor', name: '복도' },
        'B3-D6' => { type: 'corridor', name: '복도' },
        'B3-E6' => { type: 'corridor', name: '복도' },
        'B3-F6' => { type: 'corridor', name: '복도' },
        'B3-G6' => { type: 'corridor', name: '복도' },
        'B3-H6' => { type: 'wall', name: '벽' },
        
        'B3-A7' => { type: 'wall', name: '벽' },
        'B3-B7' => { type: 'corridor', name: '복도' },
        'B3-C7' => { type: 'corridor', name: '복도' },
        'B3-D7' => { type: 'corridor', name: '복도' },
        'B3-E7' => { type: 'corridor', name: '복도' },
        'B3-F7' => { type: 'entrance', name: '입구' },
        'B3-G7' => { type: 'corridor', name: '복도' },
        'B3-H7' => { type: 'wall', name: '벽' },
        
        'B3-A8' => { type: 'wall', name: '벽' },
        'B3-B8' => { type: 'wall', name: '벽' },
        'B3-C8' => { type: 'wall', name: '벽' },
        'B3-D8' => { type: 'wall', name: '벽' },
        'B3-E8' => { type: 'wall', name: '벽' },
        'B3-F8' => { type: 'wall', name: '벽' },
        'B3-G8' => { type: 'wall', name: '벽' },
        'B3-H8' => { type: 'wall', name: '벽' }
      }
    },
    
    'B4' => {
      name: '지하 4층',
      difficulty: 3,
      investigation_type: '감지',
      entrance: 'B4-F7',
      grid: {
        'B4-A1' => { type: 'wall', name: '벽' },
        'B4-B1' => { type: 'wall', name: '벽' },
        'B4-C1' => { type: 'wall', name: '벽' },
        'B4-D1' => { type: 'wall', name: '벽' },
        'B4-E1' => { type: 'wall', name: '벽' },
        'B4-F1' => { type: 'wall', name: '벽' },
        'B4-G1' => { type: 'wall', name: '벽' },
        'B4-H1' => { type: 'wall', name: '벽' },
        
        'B4-A2' => { type: 'wall', name: '벽' },
        'B4-B2' => { type: 'room', name: '감시실', investigatable: true },
        'B4-C2' => { type: 'corridor', name: '복도' },
        'B4-D2' => { type: 'room', name: '간부실', investigatable: true },
        'B4-E2' => { type: 'room', name: '간부실', investigatable: true },
        'B4-F2' => { type: 'corridor', name: '복도' },
        'B4-G2' => { type: 'room', name: '훈련장', investigatable: true },
        'B4-H2' => { type: 'wall', name: '벽' },
        
        'B4-A3' => { type: 'wall', name: '벽' },
        'B4-B3' => { type: 'corridor', name: '복도' },
        'B4-C3' => { type: 'corridor', name: '복도' },
        'B4-D3' => { type: 'corridor', name: '복도' },
        'B4-E3' => { type: 'corridor', name: '복도' },
        'B4-F3' => { type: 'corridor', name: '복도' },
        'B4-G3' => { type: 'corridor', name: '복도' },
        'B4-H3' => { type: 'wall', name: '벽' },
        
        'B4-A4' => { type: 'wall', name: '벽' },
        'B4-B4' => { type: 'corridor', name: '복도' },
        'B4-C4' => { type: 'room', name: '비밀창고', investigatable: true },
        'B4-D4' => { type: 'corridor', name: '복도' },
        'B4-E4' => { type: 'corridor', name: '복도' },
        'B4-F4' => { type: 'room', name: '마법연구실', investigatable: true },
        'B4-G4' => { type: 'corridor', name: '복도' },
        'B4-H4' => { type: 'wall', name: '벽' },
        
        'B4-A5' => { type: 'wall', name: '벽' },
        'B4-B5' => { type: 'corridor', name: '복도' },
        'B4-C5' => { type: 'corridor', name: '복도' },
        'B4-D5' => { type: 'corridor', name: '복도' },
        'B4-E5' => { type: 'corridor', name: '복도' },
        'B4-F5' => { type: 'corridor', name: '복도' },
        'B4-G5' => { type: 'corridor', name: '복도' },
        'B4-H5' => { type: 'wall', name: '벽' },
        
        'B4-A6' => { type: 'wall', name: '벽' },
        'B4-B6' => { type: 'corridor', name: '복도' },
        'B4-C6' => { type: 'corridor', name: '복도' },
        'B4-D6' => { type: 'corridor', name: '복도' },
        'B4-E6' => { type: 'corridor', name: '복도' },
        'B4-F6' => { type: 'corridor', name: '복도' },
        'B4-G6' => { type: 'corridor', name: '복도' },
        'B4-H6' => { type: 'wall', name: '벽' },
        
        'B4-A7' => { type: 'wall', name: '벽' },
        'B4-B7' => { type: 'corridor', name: '복도' },
        'B4-C7' => { type: 'corridor', name: '복도' },
        'B4-D7' => { type: 'corridor', name: '복도' },
        'B4-E7' => { type: 'corridor', name: '복도' },
        'B4-F7' => { type: 'entrance', name: '입구' },
        'B4-G7' => { type: 'corridor', name: '복도' },
        'B4-H7' => { type: 'wall', name: '벽' },
        
        'B4-A8' => { type: 'wall', name: '벽' },
        'B4-B8' => { type: 'wall', name: '벽' },
        'B4-C8' => { type: 'wall', name: '벽' },
        'B4-D8' => { type: 'wall', name: '벽' },
        'B4-E8' => { type: 'wall', name: '벽' },
        'B4-F8' => { type: 'wall', name: '벽' },
        'B4-G8' => { type: 'wall', name: '벽' },
        'B4-H8' => { type: 'wall', name: '벽' }
      }
    },
    
    'B5' => {
      name: '지하 5층',
      difficulty: 4,
      investigation_type: '훔쳐보기',
      entrance: 'B5-F7',
      grid: {
        'B5-A1' => { type: 'wall', name: '벽' },
        'B5-B1' => { type: 'wall', name: '벽' },
        'B5-C1' => { type: 'wall', name: '벽' },
        'B5-D1' => { type: 'wall', name: '벽' },
        'B5-E1' => { type: 'wall', name: '벽' },
        'B5-F1' => { type: 'wall', name: '벽' },
        'B5-G1' => { type: 'wall', name: '벽' },
        'B5-H1' => { type: 'wall', name: '벽' },
        
        'B5-A2' => { type: 'wall', name: '벽' },
        'B5-B2' => { type: 'room', name: '비밀문서고', investigatable: true },
        'B5-C2' => { type: 'corridor', name: '복도' },
        'B5-D2' => { type: 'room', name: '핵심인물실', investigatable: true },
        'B5-E2' => { type: 'room', name: '핵심인물실', investigatable: true },
        'B5-F2' => { type: 'corridor', name: '복도' },
        'B5-G2' => { type: 'room', name: '금고', investigatable: true },
        'B5-H2' => { type: 'wall', name: '벽' },
        
        'B5-A3' => { type: 'wall', name: '벽' },
        'B5-B3' => { type: 'corridor', name: '복도' },
        'B5-C3' => { type: 'corridor', name: '복도' },
        'B5-D3' => { type: 'corridor', name: '복도' },
        'B5-E3' => { type: 'corridor', name: '복도' },
        'B5-F3' => { type: 'corridor', name: '복도' },
        'B5-G3' => { type: 'corridor', name: '복도' },
        'B5-H3' => { type: 'wall', name: '벽' },
        
        'B5-A4' => { type: 'wall', name: '벽' },
        'B5-B4' => { type: 'room', name: '사령관실', investigatable: true },
        'B5-C4' => { type: 'corridor', name: '복도' },
        'B5-D4' => { type: 'corridor', name: '복도' },
        'B5-E4' => { type: 'corridor', name: '복도' },
        'B5-F4' => { type: 'corridor', name: '복도' },
        'B5-G4' => { type: 'room', name: '전략실', investigatable: true },
        'B5-H4' => { type: 'wall', name: '벽' },
        
        'B5-A5' => { type: 'wall', name: '벽' },
        'B5-B5' => { type: 'corridor', name: '복도' },
        'B5-C5' => { type: 'corridor', name: '복도' },
        'B5-D5' => { type: 'corridor', name: '복도' },
        'B5-E5' => { type: 'corridor', name: '복도' },
        'B5-F5' => { type: 'corridor', name: '복도' },
        'B5-G5' => { type: 'corridor', name: '복도' },
        'B5-H5' => { type: 'wall', name: '벽' },
        
        'B5-A6' => { type: 'wall', name: '벽' },
        'B5-B6' => { type: 'corridor', name: '복도' },
        'B5-C6' => { type: 'corridor', name: '복도' },
        'B5-D6' => { type: 'corridor', name: '복도' },
        'B5-E6' => { type: 'corridor', name: '복도' },
        'B5-F6' => { type: 'corridor', name: '복도' },
        'B5-G6' => { type: 'corridor', name: '복도' },
        'B5-H6' => { type: 'wall', name: '벽' },
        
        'B5-A7' => { type: 'wall', name: '벽' },
        'B5-B7' => { type: 'corridor', name: '복도' },
        'B5-C7' => { type: 'corridor', name: '복도' },
        'B5-D7' => { type: 'corridor', name: '복도' },
        'B5-E7' => { type: 'corridor', name: '복도' },
        'B5-F7' => { type: 'entrance', name: '입구' },
        'B5-G7' => { type: 'corridor', name: '복도' },
        'B5-H7' => { type: 'wall', name: '벽' },
        
        'B5-A8' => { type: 'wall', name: '벽' },
        'B5-B8' => { type: 'wall', name: '벽' },
        'B5-C8' => { type: 'wall', name: '벽' },
        'B5-D8' => { type: 'wall', name: '벽' },
        'B5-E8' => { type: 'wall', name: '벽' },
        'B5-F8' => { type: 'wall', name: '벽' },
        'B5-G8' => { type: 'wall', name: '벽' },
        'B5-H8' => { type: 'wall', name: '벽' }
      }
    }
  }

  # 적 정보
  ENEMY_STATS = {
    '순혈주의 활동가' => { hp: 40, atk: 3, def: 2, agi: 3, luck: 5, exp: 10 },
    '클라리스 지지자' => { hp: 50, atk: 4, def: 3, agi: 4, luck: 6, exp: 15 },
    '혈통차별 집행자' => { hp: 70, atk: 5, def: 4, agi: 5, luck: 8, exp: 25 },
    '클라리스 간부' => { hp: 90, atk: 6, def: 5, agi: 6, luck: 10, exp: 35 },
    '정예 순혈주의자' => { hp: 120, atk: 8, def: 6, agi: 7, luck: 12, exp: 50 },
    '클라리스 사령관' => { hp: 150, atk: 10, def: 8, agi: 8, luck: 15, exp: 75 }
  }

  @explorations = {}
  @mutex = Mutex.new

  class << self
    attr_reader :explorations

    # 탐색 시작
    def start_exploration(participants, floor_code, thread_id, sheet_manager: nil)
      @mutex.synchronize do
        map_info = FLOOR_MAPS[floor_code]
        return nil unless map_info

        exploration_id = generate_exploration_id(participants, floor_code, thread_id)

        # 입구 위치 (entrance 필드 사용)
        entrance_pos = map_info[:entrance]

        @explorations[exploration_id] = {
          exploration_id: exploration_id,
          thread_id: thread_id,
          floor: floor_code,
          floor_name: map_info[:name],
          difficulty: map_info[:difficulty],
          investigation_type: map_info[:investigation_type],
          participants: participants,
          position: entrance_pos,
          discovered_clues: [],
          found_items: [],
          defeated_enemies: [],
          current_encounter: nil,
          active: true,
          sheet_manager: sheet_manager,
          created_at: Time.now
        }

        exploration_id
      end
    end

    # 좌표로 이동
    def move_to(exploration_id, user_id, target_coord)
      exploration = get(exploration_id)
      return nil unless exploration
      return { error: '권한이 없습니다' } unless exploration[:participants].include?(user_id)
      return { error: '전투 중입니다' } if exploration[:current_encounter]

      map_info = FLOOR_MAPS[exploration[:floor]]
      
      # 좌표에 층 코드 포함 (B2-C4 형식)
      full_coord = "#{exploration[:floor]}-#{target_coord.upcase}"
      target_cell = map_info[:grid][full_coord]

      return { error: '존재하지 않는 좌표입니다' } unless target_cell
      return { error: '벽으로는 이동할 수 없습니다' } if target_cell[:type] == 'wall'

      previous_pos = exploration[:position]
      exploration[:position] = full_coord
      
      update(exploration_id, exploration)

      {
        success: true,
        from: previous_pos,
        to: full_coord,
        location: target_cell
      }
    end

    # 조사 실행
    def investigate(exploration_id, user_id, location_name)
      exploration = get(exploration_id)
      return nil unless exploration
      return { error: '권한이 없습니다' } unless exploration[:participants].include?(user_id)
      return { error: '전투 중입니다' } if exploration[:current_encounter]

      map_info = FLOOR_MAPS[exploration[:floor]]
      current_cell = map_info[:grid][exploration[:position]]

      # 현재 위치가 해당 장소인지 확인
      unless current_cell[:investigatable] && current_cell[:name] == location_name
        return { error: "이 위치에는 #{location_name}이(가) 없습니다" }
      end

      result = {
        location: location_name,
        events: []
      }

      # 단서 발견 판정
      clue_result = check_clue_discovery(exploration, user_id, location_name)
      if clue_result
        result[:events] << { type: 'clue', data: clue_result }
        exploration[:discovered_clues] << clue_result
      end

      # 아이템 발견 판정
      item_result = check_item_discovery(exploration, location_name)
      if item_result
        result[:events] << { type: 'item', data: item_result }
        exploration[:found_items] << item_result
      end

      # 적 조우 판정
      encounter_result = check_enemy_encounter(exploration, location_name)
      if encounter_result
        result[:events] << { type: 'encounter', data: encounter_result }
        exploration[:current_encounter] = encounter_result
      end

      update(exploration_id, exploration)

      result
    end

    # 맵 렌더링
    def render_map(exploration_id)
      exploration = get(exploration_id)
      return nil unless exploration

      map_info = FLOOR_MAPS[exploration[:floor]]
      grid = map_info[:grid]
      current_pos = exploration[:position]

      lines = []
      lines << "#{exploration[:floor_name]} (#{exploration[:floor]})"
      lines << "현재 위치: #{current_pos} (#{grid[current_pos][:name]})"
      lines << ""
      lines << "  A B C D E F G H"

      (1..8).each do |row|
        line = "#{row} "
        ('A'..'H').each do |col|
          coord = "#{exploration[:floor]}-#{col}#{row}"
          cell = grid[coord]

          if coord == current_pos
            line += "@ "  # 현재 위치
          elsif cell[:type] == 'wall'
            line += "■ "
          elsif cell[:type] == 'entrance'
            line += "○ "
          elsif cell[:type] == 'room'
            line += "□ "
          else
            line += "- "
          end
        end
        lines << line
      end

      lines << ""
      lines << "■: 벽 | -: 복도 | □: 방 | ○: 입구 | @: 현재위치"

      lines.join("\n")
    end

    def get(exploration_id)
      @mutex.synchronize { @explorations[exploration_id] }
    end

    def find_by_user(user_id)
      @mutex.synchronize do
        @explorations.values.find { |exp| exp[:participants].include?(user_id) && exp[:active] }
      end
    end

    def find_by_thread(thread_id)
      @mutex.synchronize do
        @explorations.values.find { |exp| exp[:thread_id] == thread_id && exp[:active] }
      end
    end

    def update(exploration_id, updates)
      @mutex.synchronize do
        @explorations[exploration_id]&.merge!(updates)
      end
    end

    def end_exploration(exploration_id)
      exploration = get(exploration_id)
      return nil unless exploration

      exploration[:active] = false
      exploration[:ended_at] = Time.now

      {
        floor: exploration[:floor_name],
        participants: exploration[:participants],
        clues_found: exploration[:discovered_clues].size,
        items_found: exploration[:found_items].size,
        enemies_defeated: exploration[:defeated_enemies].size
      }
    end

    # 심층 조사 가능 여부
    def has_deep_investigation?(exploration_id, location_name)
      exploration = get(exploration_id)
      return false unless exploration

      floor_locs = INVESTIGATION_LOCATIONS[exploration[:floor]]
      return false unless floor_locs

      floor_locs.key?(location_name)
    end

    # 심층 조사 정보 가져오기
    def get_deep_investigation_info(exploration_id, location_name)
      exploration = get(exploration_id)
      return nil unless exploration

      floor_locs = INVESTIGATION_LOCATIONS[exploration[:floor]]
      return nil unless floor_locs

      floor_locs[location_name]
    end

    # 심층 조사 시작
    def start_deep_investigation(exploration_id, location_name)
      exploration = get(exploration_id)
      return nil unless exploration

      info = get_deep_investigation_info(exploration_id, location_name)
      return nil unless info

      exploration[:deep_investigation] = {
        location: location_name,
        description: info[:description],
        sub_locations: info[:sub_locations],
        investigated: [],
        started_at: Time.now
      }

      update(exploration_id, exploration)

      exploration[:deep_investigation]
    end

    # 심층 조사 종료
    def end_deep_investigation(exploration_id)
      exploration = get(exploration_id)
      return nil unless exploration
      return nil unless exploration[:deep_investigation]

      deep_inv = exploration[:deep_investigation]
      result = {
        location: deep_inv[:location],
        investigated_count: deep_inv[:investigated].size,
        total_count: deep_inv[:sub_locations].size
      }

      exploration[:deep_investigation] = nil
      update(exploration_id, exploration)

      result
    end

    # 심층 조사 중인지 확인
    def in_deep_investigation?(exploration_id)
      exploration = get(exploration_id)
      return false unless exploration

      !exploration[:deep_investigation].nil?
    end

    # 세부 항목 조사 기록
    def record_deep_investigation(exploration_id, sub_location)
      exploration = get(exploration_id)
      return false unless exploration
      return false unless exploration[:deep_investigation]

      exploration[:deep_investigation][:investigated] << {
        sub_location: sub_location,
        investigated_at: Time.now
      }

      update(exploration_id, exploration)
      true
    end

    private

    def generate_exploration_id(participants, floor_code, thread_id)
      sorted = participants.sort.join('_')
      timestamp = Time.now.to_i
      "coord_explore_#{floor_code}_#{thread_id}_#{timestamp}"
    end

    def check_clue_discovery(exploration, user_id, location_name)
      sheet_manager = exploration[:sheet_manager]
      return nil unless sheet_manager

      # 조사 시트에서 조회
      investigation_type = exploration[:investigation_type]
      entry = sheet_manager.find_investigation_entry(location_name, investigation_type)

      return nil unless entry

      # 판정
      user = sheet_manager.find_user(user_id)
      luck = (user["행운"] || 10).to_i
      dice = rand(1..20)
      difficulty = entry["난이도"].to_i
      total = dice + luck
      success = total >= difficulty

      result_text = success ? entry["성공결과"] : entry["실패결과"]

      clue = {
        target: location_name,
        dice: dice,
        luck: luck,
        total: total,
        difficulty: difficulty,
        success: success,
        result: result_text,
        discovered_by: user_id
      }

      # 로그 기록
      sheet_manager.log_investigation(
        user_id,
        exploration[:floor_name],
        location_name,
        investigation_type,
        success,
        result_text
      )

      clue
    end

    def check_item_discovery(exploration, location_name)
      # 층별 확률
      rate = case exploration[:difficulty]
             when 1 then 30
             when 2 then 25
             when 3 then 20
             when 4 then 15
             else 20
             end

      return nil if rand(100) >= rate

      # 층별 아이템
      items = case exploration[:difficulty]
              when 1 then ['소형물약', '낡은 지도', '조직 배지']
              when 2 then ['중형물약', '암호문서', '마법 촉매']
              when 3 then ['대형물약', '비밀 열쇠', '마법서 조각']
              when 4 then ['전설의 유물', '고급 마법서', '핵심인물 서신']
              else ['소형물약']
              end

      { name: items.sample, location: location_name }
    end

    def check_enemy_encounter(exploration, location_name)
      # 층별 확률
      rate = case exploration[:difficulty]
             when 1 then 35
             when 2 then 40
             when 3 then 45
             when 4 then 50
             else 35
             end

      return nil if rand(100) >= rate

      # 층별 적
      enemies = case exploration[:difficulty]
                when 1 then ['순혈주의 활동가', '클라리스 지지자']
                when 2 then ['클라리스 지지자', '혈통차별 집행자']
                when 3 then ['혈통차별 집행자', '클라리스 간부', '정예 순혈주의자']
                when 4 then ['클라리스 간부', '정예 순혈주의자', '클라리스 사령관']
                else ['순혈주의 활동가']
                end

      enemy_name = enemies.sample
      stats = ENEMY_STATS[enemy_name]

      {
        name: enemy_name,
        full_name: "클라리스 오르 #{enemy_name}",
        hp: stats[:hp],
        max_hp: stats[:hp],
        atk: stats[:atk],
        def: stats[:def],
        agi: stats[:agi],
        luck: stats[:luck],
        exp: stats[:exp],
        location: location_name
      }
    end
  end
end
